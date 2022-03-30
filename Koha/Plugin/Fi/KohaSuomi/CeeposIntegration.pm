package Koha::Plugin::Fi::KohaSuomi::CeeposIntegration;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);
## We will also need to include any Koha libraries we want to access
use C4::Context;
use utf8;

use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Database;

## Here we set our plugin version
our $VERSION = "1.0.0";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Ceepos-kassaintegraatio',
    author          => 'Johanna Räisä',
    date_authored   => '2022-03-30',
    date_updated    => '2022-03-30',
    minimum_version => '21.11.00.000',
    maximum_version => '',
    version         => $VERSION,
    description     => 'Ceepos-kassaintegraatio',
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual 
    my $self = $class->SUPER::new($args);

    return $self;
}
## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    $self->table();
}

## This is the 'upgrade' method. It will be triggered when a newer version of a
## plugin is installed over an existing older version of a plugin
sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    return 1;
}

sub table {
    my ($self) = @_;

    my $dbh = C4::Context->dbh;
    my $transactions = $self->get_qualified_table_name('transactions');
    $dbh->do("
        CREATE TABLE ".$transactions." (
            transaction_id int(11) NOT NULL auto_increment,
            borrowernumber int(11) NOT NULL,
            accountlines_id int(11),
            status ENUM('paid','pending','cancelled','unsent','processing') DEFAULT 'unsent',
            timestamp timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            description TEXT NOT NULL,
            price_in_cents int(11) NOT NULL,
            user_branch varchar(10),
            is_self_payment int(11) NOT NULL DEFAULT 0,
            PRIMARY KEY (transaction_id),
            FOREIGN KEY (accountlines_id)
                REFERENCES accountlines(accountlines_id),
            FOREIGN KEY (borrowernumber)
                REFERENCES borrowers(borrowernumber)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ");
}

1;

