package Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions;

# Copyright 2022 KohaSuomi
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use Carp;
use Scalar::Util qw( blessed );
use Try::Tiny;
use JSON;
use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration;
use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Database;
use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::CPU;
use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions;
use C4::Context;
use Encode;
use Koha::Account::Lines;
use Data::Dumper;
use C4::Log;

sub new {
    my ($class, $params) = @_;
    my $self = {};
    $self->{_params} = $params;
    bless($self, $class);
    return $self;

}

sub db {
    my ($self) = @_;
    return Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Database->new;
}

sub cpu {
    my ($self, $branch) = @_;
    return Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::CPU->new({branch => $branch});
}

sub plugin {
    my ($self) = @_;
    return Koha::Plugin::Fi::KohaSuomi::CeeposIntegration->new;
}

sub librarycode {
    my ($self) = @_;
    return C4::Context::mybranch;
}

sub manager {
    my ($self) = @_;
    return C4::Context->userenv->{'number'};
}

sub get {
    my ($self, $id) = @_;
    return $self->db->getTransactionData($id);
}

sub list {
    my ($self, $id) = @_;
    return $self->db->listTransactions($id);
}

sub cancel {
    my ($self, $params) = @_;
    my @params = ($params->{status}, $params->{description}, $params->{transaction_id});
    return $self->db->updateTransactions(@params);
}

sub void {
    my ($self, $params) = @_;
    if ($params->{transaction_id}) {
        my @params = ($params->{status}, $params->{description}, $params->{transaction_id});
        return $self->db->updateTransactions(@params);
    } else {
        my @params = ($params->{status}, $params->{description}, $params->{payment_id});
        return $self->db->updatePayment(@params);
    }
}

sub updateStatus {
    my ($self, $params) = @_;
    if ($params->{transaction_id}) {
        my @params = ($params->{status}, $params->{transaction_id});
        return $self->db->updateTransactionStatus(@params);
    } else {
        my @params = ($params->{status}, $params->{payment_id});
        return $self->db->updatePaymentStatus(@params);
    }
}

sub getByAccountline {
    my ($self, $id) = @_;
    return $self->db->getTransactionDataByAccountline($id);
}

sub set {
    my ($self, $params) = @_;
    my @params = ($params->{transaction_id},$params->{borrowernumber},$params->{accountlines_id},$params->{status},$params->{description},$params->{payment_type},$params->{price_in_cents},$params->{manager_id}, $params->{office}, $self->librarycode);
    return $self->db->setTransactionData(@params);
}

sub setPayments {
    my ($self, $payments) = @_;

    my ( $uuid, $uuidstring );
    my $cpuid = $self->_random_string();
    my $patron_id;
    my $office;
    my $accountline_ids;
    my $total = 0;
    foreach my $payment (@$payments) {
        if ($self->_convert_to_cents($payment->{amountoutstanding}) == 0) {
            next;
        }
        unless ($payment->{office}) {
            Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::BadRequest->throw('Office is missing!');
        }
        $payment->{manager_id} = $self->manager;
        $payment->{status} = "unsent";
        $payment->{transaction_id} = $cpuid;
        $patron_id = $payment->{borrowernumber};
        $total += $payment->{amountoutstanding};
        $office = $payment->{office};
        if ($payment->{accountlines}) {
            my @lines = split(',', $payment->{accountlines});
            foreach my $accountline_id (@lines) {
                my $accountline = Koha::Account::Lines->find($accountline_id);
                $payment->{accountlines_id} = $accountline_id;
                my $amount = $self->_calculate_amount($total, $accountline->amountoutstanding);
                $payment->{price_in_cents} = $self->_convert_to_cents($amount);
                $payment->{payment_type} = $self->_convert_payment_type($accountline->debit_type_code);
                $payment->{description} = $accountline->description;
                $self->set($payment);
                push @$accountline_ids, $accountline_id;
                last if $amount < $accountline->amountoutstanding;
            }
        } else {
            my $amount = $self->_calculate_amount($total, $payment->{amountoutstanding});
            $payment->{price_in_cents} = $self->_convert_to_cents($amount);
            $payment->{payment_type} = $self->_convert_payment_type($payment->{payment_type});
            $self->set($payment);
            push @$accountline_ids, $payment->{accountlines_id};
        }
    }
    
    if ($accountline_ids) {
        my $source = $self->cpu($self->librarycode)->_get_server_config()->{source};
        $office =~ s/$source//;
        my $response = $self->cpu($self->librarycode)->sendPayments($cpuid, $patron_id, $office);
        if ($response->{error}) {
            Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::BadRequest->throw($response->{error});
        }

        foreach my $accountline_id (@$accountline_ids) {
            my $accountline = Koha::Account::Lines->find($accountline_id);
            $accountline->set({note => $cpuid})->store();
        }
    }
}

sub completePayment {
    my ($self, $params) = @_;

    my $logger = Koha::Logger->get({ interface => 'ceepos' });

    my $transactions = $self->list($params->{Id});
    my $branch = @$transactions[0]->{branch};
    
    unless (defined $transactions) {
        $logger->warn("Transaction not found ". $params->{Id});
        Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::NotFound->throw("Transaction not found");
    }

    unless ($self->cpu($branch)->is_valid_hash($params)) {
        $logger->warn("Invalid hash for transaction ".$params->{Id});
        Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::BadRequest->throw("Invalid hash for transaction ". $params->{Id});
    }

    my $status = $self->cpu($branch)->_get_response_string($params->{Status})->{status};

    if ($status ne "paid" and $status ne "cancelled") {
        $logger->warn("Invalid status $status. Call subroutine with 'cancelled' or 'paid' status");
        return;
    }

    my $office;
    my $patron_id;
    my $accountline_ids;
    my $total = 0;
    foreach my $transaction (@$transactions) {

        my $old_status = $transaction->{status};
        my $new_status = $status;

        if ($old_status eq $new_status){
            # Trying to complete with same status, makes no sense
            next;
        }

        if ($old_status ne "processing"){
            $self->updateStatus({status => "processing", payment_id => $transaction->{payment_id}});
        } else {
            # Another process is already processing the payment
            next;
        }

        # Defined accountlines_id means that the payment is already completed in Koha.
        # We don't want to make duplicate payments. So make sure it is not defined!
        #return if defined $transaction->accountlines_id;
        # Reverse the payment if old status is different than new status (and either paid or cancelled)
        if (defined $transaction->{accountlines_id} && (($old_status eq "paid" and $new_status eq "cancelled") or ($old_status eq "cancelled" and $new_status eq "paid"))){
            $self->reversePayment($transaction->{accountlines_id});
            $self->void({ status => $status, description => $transaction->{description} . "\n\nPayment was reverted after it has already been paid", payment_id => $transaction->{payment_id}});
            next;
        }

        # Payment was cancelled
        if ($new_status eq "cancelled") {
            $self->updateStatus({status => "cancelled", payment_id => $transaction->{payment_id}});
            if ( C4::Context->preference("FinesLog") ) {
                C4::Log::logaction("FINES", 'PAYMENT_CANCELLED', $transaction->{borrowernumber}, Dumper({
                    action                => 'payment_cancelled',
                    borrowernumber        => $transaction->{borrowernumber},
                    manager_id            => $transaction->{manager_id},
                }));
            }
            next;
        }
        $self->updateStatus({status => "paid", payment_id => $transaction->{payment_id}});
        $total += $self->_convert_to_euros($transaction->{price_in_cents});
        $patron_id = $transaction->{borrowernumber};
        $office = $transaction->{office};
        $branch = $transaction->{branch};
        push @$accountline_ids, $transaction->{accountlines_id};
    }
    
    if ($accountline_ids) {
        $self->payAccountlines($patron_id, $accountline_ids, $total, $office, $branch, $params->{Id});
    }

}

sub payAccountlines {
    my ($self, $patron_id, $accountline_ids, $total, $office, $branch, $note) = @_;

    my $patron = Koha::Patrons->find($patron_id);
    my $account = $patron->account;
    my @selected_accountlines;

    my $search_params = {
        borrowernumber    => $patron_id,
            amountoutstanding => { '<>' => 0 },
            accountlines_id   => { 'in' => \@$accountline_ids },
    };

    @selected_accountlines = Koha::Account::Lines->search(
        $search_params,
        { order_by => 'date' }
    );

    my $pay_result = $account->pay(
        {
            type         => 'PAYMENT',
            amount       => $total,
            library_id   => $branch,
            lines        => \@selected_accountlines,
            interface    => C4::Context->interface,
            payment_type => $office,
            note         => $note
        }
    );
}

sub reversePayment {
    my ( $self, $accountlines_id ) = @_;
    my $dbh = C4::Context->dbh;

    my $sth = $dbh->prepare('SELECT * FROM accountlines WHERE accountlines_id = ?');
    $sth->execute( $accountlines_id );
    my $row = $sth->fetchrow_hashref();
    my $amount_outstanding = $row->{'amountoutstanding'};

    if ( $amount_outstanding <= 0 ) {
        $sth = $dbh->prepare('UPDATE accountlines SET amountoutstanding = amount * -1, description = CONCAT( description, " Reversed -" ) WHERE accountlines_id = ?');
        $sth->execute( $accountlines_id );
    } else {
        $sth = $dbh->prepare('UPDATE accountlines SET amountoutstanding = 0, description = CONCAT( description, " Reversed -" ) WHERE accountlines_id = ?');
        $sth->execute( $accountlines_id );
    }

    if ( C4::Context->preference("FinesLog") ) {
        my $manager_id = 0;
        $manager_id = C4::Context->userenv->{'number'} if C4::Context->userenv;

        if ( $amount_outstanding <= 0 ) {
            $row->{'amountoutstanding'} *= -1;
        } else {
            $row->{'amountoutstanding'} = '0';
        }
        $row->{'description'} .= ' Reversed -';
        C4::Log::logaction("FINES", 'MODIFY', $row->{'borrowernumber'}, Dumper({
            action                => 'reverse_fee_payment',
            borrowernumber        => $row->{'borrowernumber'},
            old_amountoutstanding => $row->{'amountoutstanding'},
            new_amountoutstanding => 0 - $amount_outstanding,,
            accountlines_id       => $row->{'accountlines_id'},
            accountno             => $row->{'accountno'},
            manager_id            => $manager_id,
        }));

    }

}

sub _random_string {
    my ($self) = @_;
    my @set = ('0' ..'9', 'A' .. 'F');
    my $str = join '' => map $set[rand @set], 1 .. 24;
    return $str;
}

sub _calculate_amount {
    my ($self, $total, $amountoutstanding) = @_;

    my $amount = $total-$amountoutstanding;
    if ($amount < 0) {
        return $total;
    } else {
        return $amountoutstanding;
    }
}

sub _convert_to_cents {
    my ($self, $price) = @_;

    return sprintf "%.0f", $price*100; # convert into cents
}

sub _convert_to_euros {
    my ($self, $price) = @_;

    return sprintf "%.6f", $price/100; # convert into euros/dollars
}

sub _convert_payment_type {
    my ($self, $payment_type) = @_;

    my $config = YAML::XS::Load(Encode::encode_utf8($self->plugin->retrieve_data('ceeposintegration')));
    unless ($config->{$self->librarycode}->{$payment_type}) {
       Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::BadRequest->throw('Missing '.$payment_type.' from configuration!');
    }
    $payment_type = $config->{$self->librarycode}->{$payment_type};
    return $payment_type;
}

1;