package Koha::Plugin::Fi::KohaSuomi::CeeposIntegration;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);
## We will also need to include any Koha libraries we want to access
use C4::Context;
use utf8;
use JSON;
use YAML::XS;
use Encode;

use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::Database;

## Here we set our plugin version
our $VERSION = "1.1.0";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Ceepos-kassaintegraatio',
    author          => 'Johanna Räisä',
    date_authored   => '2022-03-30',
    date_updated    => '2023-12-15',
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

## If your tool is complicated enough to needs it's own setting/configuration
## you will want to add a 'configure' method to your plugin like so.
## Here I am throwing all the logic into the 'configure' method, but it could
## be split up like the 'report' method is.
sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'config.tt' });

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            ceeposintegration => $self->retrieve_data('ceeposintegration')
        );

        print $cgi->header(-charset    => 'utf-8');
        print $template->output();
    }
    else {
        $self->store_data(
            {
                ceeposintegration  => $cgi->param('ceeposintegration')
            }
        );
        $self->go_home();
    }
}

## If your plugin needs to add some javascript in the staff intranet, you'll want
## to return that javascript here. Don't forget to wrap your javascript in
## <script> tags. By not adding them automatically for you, you'll have a
## chance to include other javascript files if necessary.
sub intranet_js {
    my ( $self ) = @_;

    my $pluginpath = $self->get_plugin_http_path();
    my $config = YAML::XS::Load(Encode::encode_utf8($self->retrieve_data('ceeposintegration')));
    my $configKeys = join("','", keys %$config);
    my $scripts = "<script>var ceeposBranches = ['".$configKeys."']; // Define the button visibility by library</script>";
    $scripts .= '<script src="'.$pluginpath.'/js/ceeposButton.js"></script>';
    return $scripts;
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

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_namespace {
    my ( $self ) = @_;
    
    return 'kohasuomi';
}

sub table {
    my ($self) = @_;

    my $dbh = C4::Context->dbh;
    my $transactions = $self->get_qualified_table_name('transactions');
    $dbh->do("
        CREATE TABLE IF NOT EXISTS ".$transactions." (
            payment_id int(11) NOT NULL auto_increment,
            transaction_id varchar(150) NOT NULL,
            borrowernumber int(11) DEFAULT NULL,
            accountlines_id int(11) NOT NULL,
            status ENUM('paid','pending','cancelled','unsent','processing') DEFAULT 'unsent',
            timestamp timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            description TEXT NOT NULL,
            payment_type TEXT NOT NULL,
            price_in_cents int(11) NOT NULL,
            manager_id int(11) NOT NULL,
            office varchar(50) NOT NULL,
            branch varchar(20) NOT NULL,
            PRIMARY KEY (payment_id),
            FOREIGN KEY (accountlines_id)
                REFERENCES accountlines(accountlines_id),
            FOREIGN KEY (borrowernumber)
                REFERENCES borrowers(borrowernumber) ON DELETE SET NULL ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ");
}

1;

