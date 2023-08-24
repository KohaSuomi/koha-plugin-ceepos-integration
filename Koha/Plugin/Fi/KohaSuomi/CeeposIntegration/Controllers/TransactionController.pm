package Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Controllers::TransactionController;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;

use Data::Dumper;
use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions;

use Log::Log4perl;
use File::Basename;

my $CONFPATH = dirname($ENV{'KOHA_CONF'});
my $log_conf = $CONFPATH . "/log4perl.conf";
Log::Log4perl::init($log_conf);

sub pay {
    my $c = shift->openapi->valid_input or return;
    
    my $logger = Log::Log4perl->get_logger('ceepos');
    return try {
        my $params = $c->req->json;
        $logger->info("Payments received: ".Dumper($params));

        my $transaction = Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions->new();
        $transaction->setPayments($params);

        return $c->render( status => 200, openapi => "");
    }
    catch {
        my $error = $_;

        if ($error->isa("Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::BadRequest")) {
            return $c->render( status  => 400,
                            openapi => { error => $error->message});
        }
        $logger->error($error);
        return $c->render( status  => 500,
                            openapi => { error => "Something went wrong, check the logs!"});
    };
}

sub report {
    my $c = shift->openapi->valid_input or return;

    my $logger = Log::Log4perl->get_logger('ceepos');
    return try {
        my $params = $c->req->json;

        $logger->info("Report received: ".Dumper($params));

        my $transaction = Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Transactions->new();
        $transaction->completePayment($params);

        return $c->render( status => 200, openapi => "");
    }
    catch {
        my $error = $_;

        if ($error->isa("Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::BadRequest")) {
            return $c->render( status  => 400,
                            openapi => { error => $error->message});
        }
        if ($error->isa("Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Exceptions::NotFound")) {
            return $c->render( status  => 404,
                            openapi => { error => $error->message});
        }
        $logger->error($error);
        return $c->render( status  => 500,
                            openapi => { error => "Something went wrong, check the logs!"});
    };
}

1;