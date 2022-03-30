package Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Database;

# Copyright 2022 Koha-Suomi Oy
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
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
use Carp;
use Scalar::Util qw( blessed );
use Try::Tiny;
use JSON;
use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration;
use C4::Context;

=head new

    my $labels = Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Labels->new($params);

=cut

sub new {
    my ($class, $params) = @_;
    my $self = {};
    $self->{_params} = $params;
    bless($self, $class);
    return $self;

}

sub plugin {
    my ($self) = @_;
    return Koha::Plugin::Fi::KohaSuomi::CeeposIntegration->new;
}

sub transactions {
    my ($self) = @_;
    return $self->plugin->get_qualified_table_name('transactions');
}

sub dbh {
    my ($self) = @_;
    return C4::Context->dbh;
}

sub getTransactionData {
    my ($self, $id) = @_;

    my $sth = $self->dbh->prepare("SELECT * FROM ".$self->transactions." WHERE transaction_id = ?;");
    $sth->execute($id);
    return $sth->fetchrow_hashref;

}

sub setTransactionData {
    my ($self, @params) = @_;
    
    my $sth=$self->dbh->prepare("INSERT INTO ".$self->transactions." 
    (borrowernumber,accountlines_id,status,description,price_in_cents,user_branch,is_self_payment) 
    VALUES (?,?,?,?,?,?,?);");
    $sth->execute(@params);
    return $sth->{mysql_insertid};
    
}

sub updateTransactionStatus {
    my ($self, @params) = @_;
    
    my $sth=$self->dbh->prepare("UPDATE ".$self->transactions." SET status = ? WHERE id = ?;");
    return $sth->execute(@params);
    
}

1;