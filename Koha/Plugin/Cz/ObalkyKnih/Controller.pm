package Koha::Plugin::Cz::ObalkyKnih::Controller;

# REST controller: GET /api/v1/contrib/obalkyknih/covers
#
# Copyright 2026 Ján Dugovič
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.

use Modern::Perl;
use utf8;

use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;

use Koha::Biblios;
use Koha::Plugin::Cz::ObalkyKnih;
use Koha::Plugin::Cz::ObalkyKnih::Client;
use Koha::Plugin::Cz::ObalkyKnih::Identifiers;

=head1 NAME

Koha::Plugin::Cz::ObalkyKnih::Controller

=head1 API

    GET /api/v1/contrib/obalkyknih/covers?biblionumber=12&biblionumber=13&isbn=9788074151330

Anonymous and read-only. Returns

    { items => { "b12" => {...}, "i9788074151330" => {...} }, error => "..."? }

where each item carries only cover/TOC URLs, the backlink and the annotation.
Records with no cover are left out.

=cut

sub covers {
    my $c = shift->openapi->valid_input or return;

    my $plugin = Koha::Plugin::Cz::ObalkyKnih->new;
    my $max    = $Koha::Plugin::Cz::ObalkyKnih::Client::MAX_BATCH;

    my $params = $c->req->query_params;
    my @bns    = grep {/^\d{1,10}$/} @{ $params->every_param('biblionumber') };
    my @isbns  = grep { length && length() < 40 } @{ $params->every_param('isbn') };
    my %seen;
    @bns   = grep { !$seen{"b$_"}++ } @bns;
    @isbns = grep { !$seen{"i$_"}++ } @isbns;
    splice @bns, $max if @bns > $max;
    splice @isbns, $max - @bns if @bns + @isbns > $max;

    my $is_opac = ( $params->param('interface') // 'opac' ) ne 'staff';
    return $c->render( status => 200, openapi => { items => {} } )
        unless $plugin->setting( $is_opac ? 'enable_opac' : 'enable_staff' );

    my ( @keys, @queries );
    for my $bn (@bns) {
        my $q = try { _query_for_biblio($bn) };
        next unless $q;
        push @keys,    "b$bn";
        push @queries, $q;
    }
    for my $isbn (@isbns) {
        my $q = Koha::Plugin::Cz::ObalkyKnih::Client::normalise_query( { isbn => $isbn } ) or next;
        push @keys,    "i$isbn";
        push @queries, $q;
    }

    my %items;
    my $error;
    if (@queries) {
        my $res = try { $plugin->client->books( \@queries ) } catch { { error => 'internal', items => [] } };
        $error = $res->{error};
        for my $i ( 0 .. $#keys ) {
            $items{ $keys[$i] } = $res->{items}[$i] if $res->{items}[$i];
        }
    }

    my $ttl = $plugin->setting('cache_ttl');
    $c->res->headers->cache_control( $ttl > 0 ? "public, max-age=$ttl" : 'no-store' );
    return $c->render(
        status  => 200,
        openapi => { items => \%items, ( $error ? ( error => $error ) : () ) },
    );
}

# Identifiers come from the record; suppressed records get nothing, so the
# route cannot be used to look into hidden records.
sub _query_for_biblio {
    my ($bn) = @_;
    my $biblio = Koha::Biblios->find($bn) or return;
    # A method in 24.11, a column accessor (AUTOLOAD) in 26.05.
    if ( C4::Context->preference('OpacSuppression') ) {
        return if try { $biblio->opac_suppressed };
    }
    return if try { $biblio->hidden_in_opac( { rules => C4::Context->yaml_preference('OpacHiddenItems') // {} } ) };
    my $record = $biblio->metadata->record or return;
    return Koha::Plugin::Cz::ObalkyKnih::Identifiers::from_marc($record);
}

1;
