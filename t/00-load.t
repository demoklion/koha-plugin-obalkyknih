use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/..";

use Test::More;

# The Koha-facing modules need a Koha installation (koha-testing-docker).
# Without one, only the standalone modules are checked.
my $has_koha = eval { require C4::Context; require Koha::Plugins::Base; 1 };

use_ok('Koha::Plugin::Cz::ObalkyKnih::Client');
use_ok('Koha::Plugin::Cz::ObalkyKnih::Identifiers');

SKIP: {
    skip 'Koha not on @INC', 4 unless $has_koha;

    use_ok('Koha::Plugin::Cz::ObalkyKnih');
    use_ok('Koha::Plugin::Cz::ObalkyKnih::Controller');

    my $class = 'Koha::Plugin::Cz::ObalkyKnih';
    can_ok( $class, qw( configure api_routes static_routes api_namespace opac_js intranet_js opac_cover_images intranet_cover_images ) );

    require JSON;
    my $dir = "$FindBin::Bin/../Koha/Plugin/Cz/ObalkyKnih";
    my $ok  = 1;
    for my $f (qw( openapi.json staticapi.json )) {
        open my $fh, '<', "$dir/$f" or do { $ok = 0; next };
        local $/;
        $ok &&= eval { JSON::decode_json(<$fh>); 1 };
    }
    ok $ok, 'route specs are valid JSON';
}

done_testing;
