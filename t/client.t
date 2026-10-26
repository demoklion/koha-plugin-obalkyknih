use strict;
use warnings;
use utf8;
use open qw( :std :encoding(UTF-8) );

use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/..";

use JSON qw( encode_json decode_json );
use Test::More;
use URI;
use URI::QueryParam;

use FakeUA;
use Koha::Plugin::Cz::ObalkyKnih::Client;

my $C = 'Koha::Plugin::Cz::ObalkyKnih::Client';

my $record = {
    bibinfo             => { isbn => '9788074151330' },
    cover_medium_url    => 'http://cache.obalkyknih.cz/file/cover/1641988/medium',
    cover_icon_url      => 'https://cache.obalkyknih.cz/file/cover/1641988/icon',
    cover_thumbnail_url => 'https://evil.example/x.jpg',
    backlink_url        => 'https://www.obalkyknih.cz/view?isbn=9788074151330',
    toc_thumbnail_url   => 'https://cache.obalkyknih.cz/file/toc/376142/thumbnail',
    toc_pdf_url         => 'javascript:alert(1)',
    annotation          => { html => 'Kniha o <b>něčem</b> &amp; dalším', source => 'Národní knihovna ČR' },
    reviews             => [ { html_text => 'x' } ],
    orig_width          => '1333',
    orig_height         => '1900',
};

subtest 'normalise_query' => sub {
    is_deeply $C->can('normalise_query')->( { isbn => '80-7203-123-x (váz.)' } ), { isbn => '807203123X' },
        'ISBN-10 cleaned, qualifier dropped';
    is_deeply $C->can('normalise_query')->( { issn => '1210-8510' } ), { isbn => '12108510' }, 'ISSN goes into isbn';
    is_deeply $C->can('normalise_query')->( { isbn => [ '978-80-86964-09-6', '9788086964096', 'junk' ], nbn => 'CNB000154538' } ),
        { isbn => '9788086964096', nbn => 'cnb000154538' }, 'dedup, nbn lowercased, junk dropped';
    is_deeply $C->can('normalise_query')->( { isbn => [ '9788086964096', '80-7203-123-X' ] } ),
        { isbn => '9788086964096' }, 'several ISBNs of one work: first valid one sent';
    is_deeply $C->can('normalise_query')->( { oclc => '(OCoLC)311597120' } ), { oclc => '(OCoLC)311597120' }, 'oclc';
    is $C->can('normalise_query')->( { isbn => 'abc', nbn => 'cnb1' } ), undef, 'nothing usable';
    is_deeply $C->can('normalise_query')->( { isbn => '9788074151330', part_no => " 2\n" } ),
        { isbn => '9788074151330', part_no => '2' }, 'part fields kept and trimmed';
};

subtest 'success: sanitising, order, extra fields dropped' => sub {
    my $ua = FakeUA->new(
        'cache.obalkyknih.cz/api/books' => sub {
            my ($uri) = @_;
            my $multi = decode_json( $uri->query_param('multi') );
            is scalar @$multi, 2, 'only valid queries are sent';
            return [ 200, encode_json( [$record] ) ];
        },
    );
    my $c   = $C->new( ua => $ua );
    my $res = $c->books( [ { isbn => 'nothing' }, { isbn => '9780000000002' }, { isbn => '978-80-7415-133-0' } ] );
    is $res->{error}, undef, 'no error';
    is $res->{items}[0], undef, 'invalid query gives undef';
    is $res->{items}[1], undef, 'unmatched query gives undef (paired by bibinfo, not position)';
    my $it = $res->{items}[2];
    is $it->{cover_medium_url}, 'https://cache.obalkyknih.cz/file/cover/1641988/medium', 'http upgraded to https';
    ok !exists $it->{cover_thumbnail_url}, 'foreign host dropped';
    ok !exists $it->{toc_pdf_url},         'javascript: URL dropped';
    ok !exists $it->{reviews},             'reviews not passed on';
    is $it->{backlink_url}, 'https://www.obalkyknih.cz/view?isbn=9788074151330', 'backlink kept';
    is_deeply $it->{annotation}, { text => 'Kniha o něčem & dalším', source => 'Národní knihovna ČR' }, 'annotation as plain text';
    is $it->{orig_width}, 1333, 'dimensions numeric';
};

subtest 'record without backlink is not shown' => sub {
    my %r = %$record;
    delete $r{backlink_url};
    my $ua = FakeUA->new( 'cache.obalkyknih.cz/api/books' => [ 200, encode_json( [ \%r ] ) ] );
    my $res = $C->new( ua => $ua )->books( [ { isbn => '9788074151330' } ] );
    is $res->{items}[0], undef, 'dropped';
};

subtest 'failover on 5xx, penalty, host rewrite' => sub {
    my $t  = 1000;
    my $ua = FakeUA->new(
        'cache.obalkyknih.cz/api/books'  => [ 502, 'Bad gateway' ],
        'cache2.obalkyknih.cz/api/books' => [ 200, encode_json( [$record] ) ],
    );
    my $c   = $C->new( ua => $ua, now => sub {$t} );
    my $res = $c->books( [ { isbn => '9788074151330' } ] );
    is $res->{server}, 'https://cache2.obalkyknih.cz', 'answered by backup';
    is $res->{items}[0]{cover_medium_url}, 'https://cache2.obalkyknih.cz/file/cover/1641988/medium',
        'image host follows the answering server';
    is $res->{items}[0]{backlink_url}, 'https://www.obalkyknih.cz/view?isbn=9788074151330', 'www backlink untouched';

    $ua->{log} = [];
    $c->books( [ { isbn => '9788074151330' } ] );
    is( ( URI->new( ( $ua->requests )[0] )->host ), 'cache2.obalkyknih.cz', 'primary skipped while penalised' );

    $t += 3601;
    $ua->{log} = [];
    $c->books( [ { isbn => '9788074151330' } ] );
    is( ( URI->new( ( $ua->requests )[0] )->host ), 'cache.obalkyknih.cz', 'primary retried after 1 h' );
};

subtest 'penalty shared through cache' => sub {
    my $cache = FakeCache->new;
    my $ua    = FakeUA->new(
        'cache.obalkyknih.cz/api/books'  => [ 503, '' ],
        'cache2.obalkyknih.cz/api/books' => [ 200, '[]' ],
    );
    $C->new( ua => $ua, cache => $cache )->books( [ { isbn => '9788074151330' } ] );
    $ua->{log} = [];
    $C->new( ua => $ua, cache => $cache )->books( [ { isbn => '9788074151330' } ] );
    is( ( URI->new( ( $ua->requests )[0] )->host ), 'cache2.obalkyknih.cz', 'second worker skips the dead server' );
    ok !grep( {/obalkyknih:books:/} keys %{ $cache->{data} } ), 'no metadata cached when TTL is 0';
};

subtest 'timeout: dead server vs. slow cold record' => sub {
    my $ua = FakeUA->new(
        'cache.obalkyknih.cz/api/books'          => [ 500, '', { timeout => 1 } ],
        'cache.obalkyknih.cz/api/runtime/alive'  => [ 500, '', { timeout => 1 } ],
        'cache2.obalkyknih.cz/api/books'         => [ 200, encode_json( [$record] ) ],
    );
    my $res = $C->new( ua => $ua )->books( [ { isbn => '9788074151330' } ] );
    is $res->{server}, 'https://cache2.obalkyknih.cz', 'dead primary: failed over';

    my $ua2 = FakeUA->new(
        'cache.obalkyknih.cz/api/books'         => [ 500, '', { timeout => 1 } ],
        'cache.obalkyknih.cz/api/runtime/alive' => [ 200, "ALIVE\n" ],
    );
    my $c    = $C->new( ua => $ua2 );
    my $res2 = $c->books( [ { isbn => '9788074151330' } ] );
    is $res2->{error}, 'timeout', 'slow but alive: no failover';
    is $c->_down_until('https://cache.obalkyknih.cz'), undef, 'and no penalty';
    is $ua2->timeout, 6, 'request timeout restored after alive check';
};

subtest 'not registered: no pointless failover' => sub {
    my $ua = FakeUA->new( 'cache.obalkyknih.cz/api/books' =>
            [ 404, 'Unknown referer. You need to sign up at http://www.obalkyknih.cz and provide your catalog URL' ] );
    my $res = $C->new( ua => $ua )->books( [ { isbn => '9788074151330' } ] );
    is $res->{error}, 'not_registered', 'reported';
    is scalar( $ua->requests ), 1, 'other servers not tried';
};

subtest 'all servers down' => sub {
    my $ua  = FakeUA->new();
    my $res = $C->new( ua => $ua )->books( [ { isbn => '9788074151330' } ] );
    is $res->{error}, 'unavailable', 'unavailable';
    is scalar( $ua->requests ), 3, 'each server tried once';
};

subtest 'broken JSON counts as failure' => sub {
    my $ua = FakeUA->new(
        'cache.obalkyknih.cz/api/books'  => [ 200, '<html>maintenance</html>' ],
        'cache2.obalkyknih.cz/api/books' => [ 200, '[]' ],
    );
    my $res = $C->new( ua => $ua )->books( [ { isbn => '9788074151330' } ] );
    is $res->{server}, 'https://cache2.obalkyknih.cz', 'failed over';
};

subtest 'optional metadata cache' => sub {
    my $cache = FakeCache->new;
    my $ua    = FakeUA->new( 'cache.obalkyknih.cz/api/books' => [ 200, encode_json( [$record] ) ] );
    my $c     = $C->new( ua => $ua, cache => $cache, cache_ttl => 300 );
    $c->books( [ { isbn => '9788074151330' }, { isbn => '9780000000002' } ] );
    $ua->{log} = [];
    my $res = $c->books( [ { isbn => '9788074151330' }, { isbn => '9780000000002' } ] );
    is scalar( $ua->requests ), 0, 'served from cache, negatives too';
    ok $res->{items}[0]{backlink_url}, 'hit';
    is $res->{items}[1], undef, 'cached miss';
};

subtest 'batch cap and base URL validation' => sub {
    my $ua = FakeUA->new(
        'cache.obalkyknih.cz/api/books' => sub {
            my ($uri) = @_;
            return [ 200, encode_json( [] ) ] if scalar @{ decode_json( $uri->query_param('multi') ) } <= 50;
            return [ 500, 'too many' ];
        }
    );
    my $res = $C->new( ua => $ua )->books( [ map { { isbn => sprintf '978000000%04d', $_ } } 1 .. 80 ] );
    is scalar @{ $res->{items} }, 50, 'capped at 50';
    is $res->{error}, undef, 'one request';

    my $c = $C->new( base_urls => [ 'https://evil.example', ' https://cache3.obalkyknih.cz/ ' ], ua => $ua );
    is_deeply $c->{base_urls}, ['https://cache3.obalkyknih.cz'], 'only obalkyknih.cz hosts accepted';
    ok !eval { $C->new( base_urls => ['https://evil.example'] ); 1 }, 'no valid base URL dies';
};

subtest 'test mode: mock server on another host' => sub {
    my $ua = FakeUA->new(
        'mock.lan/api/books' => [
            200,
            encode_json(
                [ {
                    bibinfo          => { isbn => '9788074151330' },
                    cover_medium_url => 'http://mock.lan/file/cover/1/medium',
                    backlink_url     => 'https://www.obalkyknih.cz/view?isbn=9788074151330',
                    toc_pdf_url      => 'http://other.lan/x.pdf',
                } ]
            )
        ],
    );
    my $c   = $C->new( base_urls => ['http://mock.lan:80/'], allow_other_hosts => 1, ua => $ua );
    my $res = $c->books( [ { isbn => '9788074151330' } ] );
    is $res->{items}[0]{cover_medium_url}, 'http://mock.lan/file/cover/1/medium', 'mock image URL kept as is';
    ok !exists $res->{items}[0]{toc_pdf_url}, 'unrelated host still dropped';

    my $ua2 = FakeUA->new(
        '127.0.0.1/api/books' => [
            200,
            encode_json(
                [ {
                    bibinfo           => { isbn => '9788074151330' },
                    cover_medium_url  => '/knihovna-mock/file/cover/1/medium',
                    toc_thumbnail_url => '//evil.example/x.png',
                    backlink_url      => 'https://www.obalkyknih.cz/view?isbn=9788074151330',
                } ]
            )
        ],
    );
    my $it = $C->new( base_urls => ['http://127.0.0.1:8591'], allow_other_hosts => 1, ua => $ua2 )
        ->books( [ { isbn => '9788074151330' } ] )->{items}[0];
    is $it->{cover_medium_url}, '/knihovna-mock/file/cover/1/medium', 'root-relative path kept in test mode';
    ok !exists $it->{toc_thumbnail_url}, 'protocol-relative URL rejected';

    my $strict = $C->new( ua => FakeUA->new( 'cache.obalkyknih.cz/api/books' => [ 200, encode_json( [ { %$record, cover_medium_url => '/x/medium' } ] ) ] ) )
        ->books( [ { isbn => '9788074151330' } ] )->{items}[0];
    ok !exists $strict->{cover_medium_url}, 'relative path rejected outside test mode';
};

done_testing;
