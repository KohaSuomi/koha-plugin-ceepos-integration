package Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::CPU;

# Copyright 2016 KohaSuomi
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

use C4::Context;

use Data::Dumper qw(Dumper);
use Digest::SHA qw(sha256_hex);
use Encode;
use HTTP::Request;
use IO::Socket::SSL;
use JSON;
use LWP::UserAgent;
use YAML::XS;

use Koha::Patron;
use Koha::Patrons;
use Koha::Items;
use Koha::Logger;

use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions;

sub new {
    my ($class, $self) = @_;

    $self = {} unless ref $self eq 'HASH';
    bless $self, $class;
    return $self;
};

sub transactions {
    my ($self) = @_;
    return Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions->new;
}

=head2 is_valid_hash

  &is_valid_hash($query);

Checks the C<$query> to determine whether Patron has
returned into the return address from online store.

Return true if yes.

=cut

sub is_valid_hash {
    my ($class, $query) = @_;

    return $query->{'Hash'} eq $class->_calculate_response_hash($query);
};

=head2 sendPayment

  &sendPayment($payment);

Sends the payment using custom interface's implementation.

=cut

sub sendPayments {
    my ($self, $transaction_id, $patron_id, $office) = @_;

    my $logger = Koha::Logger->get({ interface => 'ceepos'});

    my $payment = $self->_get_payment($transaction_id, $patron_id, $office);

    my $content = $payment; # content will be JSON string, payment will be HASH
    my $response = eval {
        $content = JSON->new->canonical(1)->encode($payment);

        my $transactions = $self->transactions->list($payment->{Id});
        return { error => "Error: No transaction found with id ".$payment->{Id}, status => 0 }
            if not $transactions;

        my $server_config = $self->_get_server_config();
        my $ua = LWP::UserAgent->new;

        if ($server_config->{'ssl_cert'}) {
            $ua->ssl_opts(
                SSL_use_cert    => 1,
                SSL_cert_file   => $server_config->{'ssl_cert'},
                SSL_key_file    => $server_config->{'ssl_key'},
                SSL_ca_file     => $server_config->{'ssl_ca_file'},
                verify_hostname => 1,
            );
        }

        $ua->timeout(500);

        my $req = HTTP::Request->new(POST => $server_config->{'url'});
        $req->header('content-type' => 'application/json');

        $req->content($content);
        $self->transactions->updateStatus({status => "pending", transaction_id => $payment->{Id}});
        $logger->info("Sent payment: ".Dumper($payment));
        my $request = $ua->request($req);

        if ($request->{_rc} != 200) {
            $logger->error('Payment '.$payment->{Id}.' did not return HTTP200 from server, but '.$request->{_rc});
            $self->transactions->cancel({status => "cancelled", description => $request->{_content}, transaction_id => $payment->{Id}});
            return { error => $request->{_content}, status => 0 };
        }

        my $response = JSON->new->utf8->canonical(1)->decode($request->{_content});

        if ($response->{Hash} ne $self->_calculate_response_hash($response)) {
            $logger->error('Payment '.$payment->{Id}.' responded with invalid hash '.$response->{Hash});
            $self->transactions->cancel({status => "cancelled", description => "Invalid hash", transaction_id => $payment->{Id}});
            return { error => "Invalid hash", status => 0 };
        }

        my $response_str = $self->_get_response_int($response->{Status});
        if (defined $response_str->{description}) {
            $logger->error('Payment '.$payment->{Id}.' returned an error: '.$response_str->{description});
            $self->transactions->cancel({status => "cancelled", description => $response_str->{description}, transaction_id => $payment->{Id}});
            return { error => $response_str->{description}, status => 0 };
        }

        return $response_str;
    };

    if ($@ || $response->{'error'}) {
        my $error = $@ || $response->{'error'};

        $logger->fatal("Payment ".$payment->{Id}." died with an error: $error");
        $self->transactions->cancel({status => "cancelled", description => $error, transaction_id => $payment->{Id}});
        return { error => "Error: " . $error, status => 0 };
    }

    return $response;
};

=head2 _calculate_payment_hash

  &_calculate_payment_hash($payment);

Calculates a SHA256 checksum out of C<$payment>.

=cut

sub _calculate_payment_hash {
    my ($class, $payment) = @_;
    my $data;

    foreach my $param (sort keys %$payment){
        next if $param eq "Hash";
        my $value = $payment->{$param};

        if (ref($payment->{$param}) eq 'ARRAY') {
            my $product_hash = $value;
            $value = "";
            foreach my $product (values @$product_hash){
                foreach my $product_data (sort keys %$product){
                    $value .= $product->{$product_data} . "&";
                }
            }
            $value =~ s/&$//g
        }
        $data .= $value . "&";
    }

    $data .= $class->_get_server_config()->{'secretKey'};
    $data = Encode::encode_utf8($data);
    return Digest::SHA::sha256_hex($data);
};

=head2 _calculate_response_hash

  &_calculate_response_hash($payment);

Calculates a SHA256 checksum out of CPU C<$response>.

=cut

sub _calculate_response_hash {
    my ($class, $resp) = @_;
    my $data = "";

    my $transaction = $class->transactions->list($resp->{Id});
    return if not $transaction;

    $data .= $resp->{Source} if defined $resp->{Source};
    $data .= "&" . $resp->{Id} if defined $resp->{Id};
    $data .= "&" . $resp->{Status} if defined $resp->{Status};
    $data .= "&" if exists $resp->{Reference};
    $data .= $resp->{Reference} if defined $resp->{Reference};
    $data .= "&" . $resp->{PaymentAddress} if defined $resp->{PaymentAddress};
    $data .= "&" . $class->_get_server_config()->{'secretKey'};

    $data =~ s/^&//g;
    $data = Digest::SHA::sha256_hex($data);
    return $data;
};

=head2 _convert_to_cpu_products

Converts payment rows to CPU product

=cut

sub _convert_to_cpu_products {
    my ($class, $products) = @_;
    my $CPU_products;

    foreach my $product (@$products){
        my $tmp;

        $tmp->{Price} = $product->{price_in_cents};
        $tmp->{Description} = $product->{description};
        $tmp->{Code} = $product->{payment_type};

        push @$CPU_products, $tmp;
    }

    return $CPU_products;
};

=head2 _get_payment

Creates a payment that has a format matching CPU's documentation.

=cut

sub _get_payment {
    my ($self, $transaction_id, $patron_id, $office) = @_;

    my $payment;
    $payment->{ApiVersion}  = "2.0";
    $payment->{Source}      = $self->_get_server_config()->{'source'};
    $payment->{Id}          = $transaction_id;
    $payment->{Mode}        = C4::Context->config('pos')->{'CPU'}->{'mode'};
    if (C4::Context->config('pos')->{'CPU'}->{'receiptDescription'} eq 'borrower') {
        my $patron = Koha::Patrons->find($patron_id);
        $payment->{Description} = $patron->surname . ", " .  $patron->firstname . " (".$patron->cardnumber.")";
    } else {
        $payment->{Description} = "#" . $transaction_id;
    }
    my $transactions = $self->transactions->list($transaction_id);
    $payment->{Products}    = $self->_convert_to_cpu_products($transactions);
    my $notificationAddress = C4::Context->config('pos')->{'CPU'}->{'notificationAddress'};
    my $transactionNumber = $transaction_id;
    $notificationAddress =~ s/{invoicenumber}/$transactionNumber/g;
    $payment->{NotificationAddress} = $notificationAddress;

    # Custom parameters
    $payment->{Office} = $office;
    # / Custom parameters

    $payment = $self->_validate_cpu_hash($payment);
    $payment->{Hash} = $self->_calculate_payment_hash($payment);
    $payment = $self->_validate_cpu_hash($payment);

    return $payment;
}

=head2 _get_response_int

  &_get_response_int($code);

Converts a response from CPU into a HASH containing "status" and "description".
Status is the same code as CPU returned, and description is additional description
for possible errors.

=cut

sub _get_response_int {
    my ($class, $code) = @_;

    my $status;
    $status->{status} = 0;
    $status->{status} = 1 if $code == 1;
    $status->{status} = 2 if $code == 2;
    $status->{description} = "ERROR 97: Duplicate id" if $code == 97;
    $status->{description} = "ERROR 98: System error" if $code == 98;
    $status->{description} = "ERROR 99: Invalid invoice" if $code == 99;

    return $status;
}

=head2 _get_response_string

  &_get_response_string($code);

Converts a response from CPU into a HASH containing "status" and "description".
Status is a string representation of payment status that matches the definitions of
C<payments_transactions.status>.

Uses _get_response_int for the description-parameter. See also _get_response_int.

=cut

sub _get_response_string {
    my ($class, $code) = @_;

    my $response = $class->_get_response_int($code);
    my $status;
    $status->{status} = 'cancelled';
    $status->{status} = 'paid' if $response->{'status'} == 1;
    $status->{status} = 'pending' if $response->{'status'} == 2;
    $status->{description} = $response->{description} if $response->{description};

    return $status;
};

=head2 _validate_cpu_hash

  &_validate_cpu_hash($payment);

Makes some basic validations on C<$payment>. CPU has some requirements, such as:
A payment may not contain
- &-character
- ('-character bug was in online payments)
- (empty description was in online payments)

Trims both ends of a value, and sets Amount and Price parameter values as int.

=cut

sub _validate_cpu_hash {
    my ($class, $invoice) = @_;

    # CPU does not like a semicolon. Go through the fields and make sure
    # none of the fields contain ';' character (from CPU documentation)
    # Also it seems that fields should be trim()med or they could cause problems
    # in SHA2 hash calculation at payment server
    foreach my $field (keys %$invoice){
        $invoice->{$field} =~ s/;//g if defined $invoice->{$field}; # Remove semicolon
        $invoice->{$field} =~ s/^\s+|\s+$//g if defined $invoice->{$field}; # Trim both ends
        my $tmp_field = $invoice->{$field};
        $tmp_field = substr($invoice->{$field}, 0, 99) if (ref($invoice->{$field}) ne "ARRAY") and ($field ne "ReturnAddress") and ($field ne "NotificationAddress");
        $tmp_field =~ s/^\s+|\s+$//g if defined $tmp_field; # Trim again, because after substr there can be again whitelines around left & right
        $invoice->{$field} = $tmp_field;
    }

    $invoice->{Mode} = int($invoice->{Mode});
    foreach my $product (@{ $invoice->{Products} }){
        foreach my $product_field (keys %$product){
            $product->{$product_field} =~ s/;//g if defined $invoice->{$product_field}; # Remove semicolon
            $product->{$product_field} =~ s/'//g if defined $invoice->{$product_field}; # Remove '
            $product->{$product_field} =~ s/^\s+|\s+$//g if defined $invoice->{$product_field}; # Trim both ends
            $product->{$product_field} = substr($product->{$product_field}, 0, 99);
            $product->{$product_field} =~ s/^\s+|\s+$//g if defined $invoice->{$product_field}; # Trim again
        }
        $product->{Description} = "-" if $product->{'Description'} eq "";
        $product->{Amount} = int($product->{Amount}) if $product->{Amount};
        $product->{Price} = int($product->{Price}) if $product->{Price};
    }

    return $invoice;
};

sub _get_server_config {
    my ($self) = @_;

    my $branchcode = $self->{'branch'};
    $branchcode ||= C4::Context::mybranch();
    my $config = C4::Context->config('pos')->{'CPU'};

    if (exists $config->{'branchcode'}->{$branchcode}) {
        $config = $config->{'branchcode'}->{$branchcode};
    }

    return $config;
}

1;
