#!/usr/bin/perl

use Modern::Perl;
use Test::More;

use FindBin;
use lib "$FindBin::Bin/../";

use Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::CPU;
use YAML::XS;
use C4::Context;
use Net::Telnet;

print "CPU test\n";

my $schema  = Koha::Database->new->schema;

my $pos_conf = C4::Context->config("pos")->{'CPU'};

ok($pos_conf, 'POS configuration exists');

my $configuration = $schema->resultset('PluginData')->find({ plugin_class => 'Koha::Plugin::Fi::KohaSuomi::CeeposIntegration', plugin_key => 'ceeposintegration' });
my $configyaml = YAML::XS::Load(Encode::encode_utf8($configuration->plugin_value));

ok($configyaml, 'Plugin configuration exists');

foreach my $key (keys %{$configyaml}) {
    my $server_config = Koha::Plugin::Fi::KohaSuomi::CeeposIntegration::Modules::CPU->new($key)->_get_server_config();
    my $source = $server_config->{'source'};
    ok($source, 'Source for '.$key.' is: '.$source);
    my ($url, $port) = $server_config->{'url'} =~ m{https?://(.+):(\d+)};
    my $telnet = Net::Telnet->new(Host => $url, Port => $port, Timeout => 10);
    my $result = $telnet->open();
    $telnet->close();
    ok($result, 'Connection to '.$server_config->{'url'}.' is open');
}

done_testing();
