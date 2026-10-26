#!/usr/bin/env perl
# A stand-in for the Obálky knih cache servers, for development instances
# whose IP is not registered at Obálky. It answers every ISBN, ČNB or OCLC
# whose last digit is even with a generated SVG "cover"; odd ones have none.
#
#   plackup -p 8591 tools/mock-obalky.psgi
#
# Then in the plugin configuration: tick "Test mode" and set the server to
# http://<host>:8591. Never use this in production.
#
# If readers' browsers cannot reach that port, proxy it under the catalogue
# (e.g. Apache ProxyPass /knihovna-mock/ http://127.0.0.1:8591/) and start it
# with MOCK_PREFIX=/knihovna-mock: image links are then root-relative.

use strict;
use warnings;
use utf8;

use JSON::PP;
use URI::Escape qw( uri_unescape );

my $json = JSON::PP->new->utf8->canonical;

sub cover_svg {
    my ( $id, $w, $h ) = @_;
    my $hue = ( unpack( '%32C*', $id ) * 37 ) % 360;
    return qq{<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" viewBox="0 0 170 240">}
        . qq{<rect width="170" height="240" fill="hsl($hue,45%,40%)"/>}
        . qq{<text x="85" y="110" fill="#fff" font-family="sans-serif" font-size="16" text-anchor="middle">MOCK</text>}
        . qq{<text x="85" y="135" fill="#fff" font-family="sans-serif" font-size="10" text-anchor="middle">$id</text></svg>};
}

my %SIZE = ( icon => [ 54, 68 ], thumbnail => [ 27, 36 ], medium => [ 170, 240 ], preview510 => [ 510, 720 ] );

my $app = sub {
    my ($env) = @_;
    my $path  = $env->{PATH_INFO} // '/';
    # MOCK_PREFIX=/knihovna-mock: image links become root-relative paths, for a
    # mock proxied under the catalogue's own origin (needs plugin test mode).
    my $base = defined $ENV{MOCK_PREFIX} && $ENV{MOCK_PREFIX} =~ m{^(/[\w\-/]*?)/?$}
        ? $1
        : ( $env->{'psgi.url_scheme'} // 'http' ) . '://' . ( $env->{HTTP_HOST} // 'localhost' );
    my %query = map { my ( $k, $v ) = split /=/, $_, 2; ( uri_unescape( $k // '' ) => uri_unescape( ( $v // '' ) =~ tr/+/ /r ) ) }
        split /&/, ( $env->{QUERY_STRING} // '' );

    if ( $path eq '/api/runtime/alive' ) {
        return [ 200, [ 'Content-Type' => 'text/plain' ], ["ALIVE\n"] ];
    }
    if ( $path eq '/api/books' ) {
        my $multi = eval { $json->decode( $query{multi} // '[]' ) } || [];
        my @out;
        for my $q (@$multi) {
            my $id = $q->{isbn} // $q->{nbn} // $q->{oclc} // next;
            $id = ref $id ? $id->[0] : $id;
            ( my $safe = $id ) =~ s/[^0-9A-Za-z]//g;
            next unless $safe =~ /[02468]$/;
            push @out, {
                bibinfo              => $q,
                backlink_url         => "https://www.obalkyknih.cz/view?isbn=$safe",
                cover_icon_url       => "$base/file/cover/$safe/icon",
                cover_thumbnail_url  => "$base/file/cover/$safe/thumbnail",
                cover_medium_url     => "$base/file/cover/$safe/medium",
                cover_preview510_url => "$base/file/cover/$safe/preview510",
                toc_thumbnail_url    => "$base/file/toc/$safe/thumbnail",
                toc_pdf_url          => "$base/file/toc/$safe/pdf",
                orig_width           => '170',
                orig_height          => '240',
                annotation           => { html => "Testovací anotace pro $safe (mock).", source => 'Mock Obálky' },
            };
        }
        return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8', 'Access-Control-Allow-Origin' => '*' ], [ $json->encode( \@out ) ] ];
    }
    if ( $path =~ m{^/file/(cover|toc)/([0-9A-Za-z]+)/(\w+)$} ) {
        my ( $kind, $id, $size ) = ( $1, $2, $3 );
        if ( $size eq 'pdf' ) {
            return [ 200, [ 'Content-Type' => 'text/plain; charset=utf-8' ], ["Mock table of contents for $id\n"] ];
        }
        my $dim = $SIZE{$size} // $SIZE{medium};
        return [ 200, [ 'Content-Type' => 'image/svg+xml' ], [ cover_svg( ( $kind eq 'toc' ? 'TOC ' : '' ) . $id, @$dim ) ] ];
    }
    return [ 404, [ 'Content-Type' => 'text/plain' ], ["not found\n"] ];
};

$app;
