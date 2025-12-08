#!/usr/bin/perl

use Modern::Perl;

use Test::More;

use Test::Mojo;

use t::lib::TestBuilder;
use t::lib::Mocks;
use Koha::Database;
use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions;
use Data::Dumper;
use YAML;
use LWP::UserAgent;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

my $ua = LWP::UserAgent->new;
my $req = HTTP::Request->new(GET => 'http://localhost:5001/');
my $res = $ua->request($req);

unless ($res->is_success) {
    plan skip_all => 'Test server not running! Start it: plackup --port 5001 t/app.psgi';
    exit;
} else {
    plan tests => 4;
}

# Mock the CPU config

t::lib::Mocks::mock_config('pos', { CPU => { url => 'http://localhost:5001/maksut', source => 'KOHA', secretKey => '12345' } });

# Test test server
my $response = $t->get_ok("http://localhost:5001/")
    ->status_is(200);

subtest 'successful payment' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 1 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid    = $patron->userid;
    my $patron_id = $patron->borrowernumber;
    my $account   = $patron->account;
    my $library_id = $patron->branchcode;
    my $amount    = 100;

    $account->add_debit(
        {   amount      => $amount,
            description => "A description",
            type        => "NEW_CARD",
            user_id     => $patron->borrowernumber,
            library_id  => $library_id,
            interface   => 'test',
        }
    );

    my $ret = $t->get_ok("//$userid:$password@/api/v1/patrons/$patron_id/account/debits")
        ->status_is(200)
        ->tx->res->json;
    is(100, $ret->[0]->{amount}, 'Total debits are 100');

    my $account_line_id = $ret->[0]->{account_line_id};

    # Mock the yaml config
    my $configuration = $schema->resultset('PluginData')->find({ plugin_class => 'Koha::Plugin::Fi::KohaSuomi::CeeposIntegration', plugin_key => 'ceeposintegration' });
    my $configyaml = YAML::Load(Encode::encode_utf8($configuration->plugin_value));
    $configyaml->{$library_id} = {
        "OVERDUE" => 1000,
    };

    $configuration->update({ plugin_value => YAML::Dump($configyaml) });

    my $params = {
        amountoutstanding => $ret->[0]->{amount},
        accountlines_id    => $account_line_id,
        description        => 'A description',
        borrowernumber     => $patron_id,
        payment_type       => 'OVERDUE',
        office             => 'KOHA',
    };

    my $payment = $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/payments/ceepos", json => [$params])
        ->status_is(200)
        ->tx->res->json;

    my $transactions = Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions->new();
    my $transaction = $transactions->getByAccountline($account_line_id);

    # Test successful payment

    my $hash = _calculate_hash({ Id => $transaction->{transaction_id}, Status => 1 });

    my $report_request = {
        Id => $transaction->{transaction_id},
        Status => 1,
        Hash => $hash,
    };

    my $report = $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/payments/ceepos/report", json => $report_request)
        ->status_is(200)
        ->tx->res->json;

    my $successful_payment = $transactions->getByAccountline($account_line_id);
    is($successful_payment->{status}, 'paid', 'Payment status is paid');
    $schema->storage->txn_rollback;
};

subtest 'cancelled payment' => sub {

    plan tests => 18;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 1 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid    = $patron->userid;
    my $patron_id = $patron->borrowernumber;
    my $account   = $patron->account;
    my $library_id = $patron->branchcode;
    my $amount    = 100;

    $account->add_debit(
        {   amount      => $amount,
            description => "A description",
            type        => "NEW_CARD",
            user_id     => $patron->borrowernumber,
            library_id  => $library_id,
            interface   => 'test',
        }
    );

    my $ret = $t->get_ok("//$userid:$password@/api/v1/patrons/$patron_id/account/debits")
        ->status_is(200)
        ->tx->res->json;
    is(100, $ret->[0]->{amount}, 'Total debits are 100');

    my $account_line_id = $ret->[0]->{account_line_id};

    # Mock the yaml config
    my $configuration = $schema->resultset('PluginData')->find({ plugin_class => 'Koha::Plugin::Fi::KohaSuomi::CeeposIntegration', plugin_key => 'ceeposintegration' });
    my $configyaml = YAML::Load(Encode::encode_utf8($configuration->plugin_value));
    $configyaml->{$library_id} = {
        "OVERDUE" => 1000,
    };

    $configuration->update({ plugin_value => YAML::Dump($configyaml) });

    my $params = {
        amountoutstanding => $ret->[0]->{amount},
        accountlines_id    => $account_line_id,
        description        => 'A description',
        borrowernumber     => $patron_id,
        payment_type       => 'OVERDUE',
        office             => 'KOHA',
    };

    my $payment = $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/payments/ceepos", json => [$params])
        ->status_is(200)
        ->tx->res->json;

    my $transactions = Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions->new();
    my $transaction = $transactions->getByAccountline($account_line_id);

    my $hash = _calculate_hash({ Id => $transaction->{transaction_id}, Status => 1 });

    my $report_request = {
        Id => $transaction->{transaction_id},
        Status => 1,
        Hash => $hash,
    };

    my $report = $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/payments/ceepos/report", json => $report_request)
        ->status_is(200)
        ->tx->res->json;

    $hash = _calculate_hash({ Id => $transaction->{transaction_id}, Status => 0 });

    $report_request = {
        Id => $transaction->{transaction_id},
        Status => 0,
        Hash => $hash,
    };

    $report = $t->post_ok("//$userid:$password@/api/v1/contrib/kohasuomi/payments/ceepos/report", json => $report_request)
        ->status_is(200)
        ->tx->res->json;

    my $cancelled_payment = $transactions->getByAccountline($account_line_id);
    is($cancelled_payment->{status}, 'cancelled', 'Payment status is cancelled');

    my $debits = $t->get_ok("//$userid:$password@/api/v1/patrons/$patron_id/account/debits")
        ->status_is(200)
        ->tx->res->json;

    my $credits = $t->get_ok("//$userid:$password@/api/v1/patrons/$patron_id/account/credits")
        ->status_is(200)
        ->tx->res->json;
    
    is($debits->[0]->{status}, 'REFUNDED', 'Payment status changed to refunded');
    is($credits->[0]->{type}, 'PAYMENT', 'Payment row added for refund');
    is($credits->[1]->{type}, 'REFUND', 'Refund row added');

    is($debits->[1]->{type}, 'PAYOUT', 'Payout row added for refund');
    

    $schema->storage->txn_rollback;
};

sub _calculate_hash {
    my ($resp) = @_;
    my $data = "";

    $data .= "&" . $resp->{Id};
    $data .= "&" . $resp->{Status};
    $data .= "&" . '12345';

    $data =~ s/^&//g;
    $data = Digest::SHA::sha256_hex($data);
    return $data;
};



done_testing();