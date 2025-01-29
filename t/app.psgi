# Description: A simple PSGI application that handles GET and POST requests
# To start: plackup -p 5001 t/app.psgi
use strict;
use warnings;
use Plack::Request;
use JSON;
use base qw(Koha::Plugins::Base);
use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions;
use Digest::SHA;

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    if ($req->path eq '/' && $req->method eq 'GET') {
        my $params = $req->parameters;
        my $response = {
            status  => 'success',
        };
        return [
            200,
            ['Content-Type' => 'application/json'],
            [encode_json($response)],
        ];
    }

    if ($req->path eq '/maksut' && $req->method eq 'POST') {
        my $params = $req->parameters;
        my $response = {
            status  => 'success',
            Hash    => _calculate_response_hash($params),
        };
        return [
            200,
            ['Content-Type' => 'application/json'],
            [encode_json($response)],
        ];
    }

    return [
        404,
        ['Content-Type' => 'text/plain'],
        ['Not Found'],
    ];
};

sub _calculate_response_hash {
    my ($resp) = @_;
    my $data = "";
    
    my $transactions = Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions->new();
    my $transaction = $transactions->list($resp->{Id});
    return if not $transaction;

    $data .= $resp->{Source} if defined $resp->{Source};
    $data .= "&" . $resp->{Id} if defined $resp->{Id};
    $data .= "&" . $resp->{Status} if defined $resp->{Status};
    $data .= "&" if exists $resp->{Reference};
    $data .= $resp->{Reference} if defined $resp->{Reference};
    $data .= "&" . $resp->{PaymentAddress} if defined $resp->{PaymentAddress};
    $data .= "&" . '12345';

    $data =~ s/^&//g;
    $data = Digest::SHA::sha256_hex($data);
    return $data;
};

return $app;