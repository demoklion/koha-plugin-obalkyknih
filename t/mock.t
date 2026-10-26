use strict;
use warnings;
use utf8;
use open qw( :std :encoding(UTF-8) );

use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/..";

use HTTP::Response;
use Test::More;
use URI;

use Koha::Plugin::Cz::ObalkyKnih::Client;

# The client talks to tools/mock-obalky.psgi through a tiny in-process UA.
my $app = do "$FindBin::Bin/../tools/mock-obalky.psgi" or die $@ || $!;

{
    package PsgiUA;
    sub new { bless { app => $_[1], t => 6 }, $_[0] }
    sub timeout { my $o = $_[0]{t}; $_[0]{t} = $_[1] if defined $_[1]; $o }
    sub get {
        my ( $self, $url ) = @_;
        my $u   = URI->new($url);
        my $res = $self->{app}->( { PATH_INFO => $u->path, QUERY_STRING => $u->query // '', HTTP_HOST => $u->host_port, 'psgi.url_scheme' => $u->scheme } );
        my $r   = HTTP::Response->new( $res->[0] );
        $r->header(@{ $res->[1] });
        $r->content( join '', @{ $res->[2] } );
        return $r;
    }
}

my $C = 'Koha::Plugin::Cz::ObalkyKnih::Client';

subtest 'absolute URLs' => sub {
    local $ENV{MOCK_PREFIX};
    my $c   = $C->new( base_urls => ['http://mock.lan:8591'], allow_other_hosts => 1, ua => PsgiUA->new($app) );
    my $res = $c->books( [ { isbn => '9788074151330' }, { isbn => '9788074151331' } ] );
    is $res->{error}, undef, 'no error';
    is $res->{items}[0]{cover_medium_url}, 'http://mock.lan:8591/file/cover/9788074151330/medium', 'even ISBN has a cover';
    is $res->{items}[1], undef, 'odd ISBN has none';
    like $res->{items}[0]{annotation}{text}, qr/mock/, 'annotation';
    ok $c->status->[0]{alive}, 'alive endpoint';
};

subtest 'MOCK_PREFIX gives root-relative paths' => sub {
    local $ENV{MOCK_PREFIX} = '/knihovna-mock';
    my $c  = $C->new( base_urls => ['http://127.0.0.1:8591'], allow_other_hosts => 1, ua => PsgiUA->new($app) );
    my $it = $c->books( [ { isbn => '9788074151330' } ] )->{items}[0];
    is $it->{cover_medium_url}, '/knihovna-mock/file/cover/9788074151330/medium', 'relative cover path';
    is $it->{toc_pdf_url},      '/knihovna-mock/file/toc/9788074151330/pdf',      'relative TOC path';
};

subtest 'image endpoint' => sub {
    my $res = $app->( { PATH_INFO => '/file/cover/9788074151330/icon', QUERY_STRING => 'keywords=x' } );
    is $res->[0], 200, '200';
    like join( '', @{ $res->[2] } ), qr/<svg[^>]+width="54"/, 'SVG at icon size';
};

done_testing;
