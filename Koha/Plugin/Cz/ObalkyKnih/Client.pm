package Koha::Plugin::Cz::ObalkyKnih::Client;

# Server-side client for the Obálky knih metadata API (/api/books).
#
# Copyright 2026 Ján Dugovič
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.

use strict;
use warnings;
use utf8;

use JSON qw( decode_json encode_json );
use LWP::UserAgent;
use URI;
use URI::Escape qw( uri_escape_utf8 );

# Order matters: this is the failover order from the Obálky manual.
our @DEFAULT_BASE_URLS = (
    'https://cache.obalkyknih.cz',
    'https://cache2.obalkyknih.cz',
    'https://cache3.obalkyknih.cz',
);

our $MAX_BATCH = 50;

# Fields copied from an Obálky record into our response. Everything else
# (reviews, ratings, OCR text, citations) is dropped.
my @URL_FIELDS = qw(
    cover_icon_url cover_thumbnail_url cover_medium_url cover_preview510_url
    toc_thumbnail_url toc_pdf_url backlink_url
);

=head1 NAME

Koha::Plugin::Cz::ObalkyKnih::Client - Obálky knih API client with failover

=head1 SYNOPSIS

    my $client = Koha::Plugin::Cz::ObalkyKnih::Client->new(
        base_urls => [ 'https://cache.obalkyknih.cz', 'https://cache2.obalkyknih.cz' ],
        cache     => $koha_cache,    # optional, get_from_cache/set_in_cache
        cache_ttl => 0,              # metadata cache, off by default
    );
    my $result = $client->books( [ { isbn => '9788074151330' } ] );

=head1 DESCRIPTION

Calls C</api/books?multi=...> on the first healthy Obálky server. A server that
fails (network error, timeout, 5xx, broken JSON) is skipped for C<penalty>
seconds, as the Obálky manual asks, and the next server is tried. A timeout on
a server whose C</api/runtime/alive> still answers C<ALIVE> is treated as a
slow (cold) record, not as a dead server.

Only URLs on C<https://*.obalkyknih.cz> survive sanitising.

=cut

sub new {
    my ( $class, %args ) = @_;
    my $other = $args{allow_other_hosts} ? 1 : 0;
    my $self  = bless {
        base_urls     => [ map { _normalise_base( $_, $other ) } @{ $args{base_urls} || [@DEFAULT_BASE_URLS] } ],
        timeout      => $args{timeout}       // 6,
        alive_timeout => $args{alive_timeout} // 3,
        penalty       => $args{penalty}       // 3600,
        cache         => $args{cache},
        cache_ttl     => $args{cache_ttl}     // 0,
        rewrite_host  => $args{rewrite_host}  // 1,
        user_agent    => $args{user_agent}    // 'koha-plugin-obalkyknih',
        now           => $args{now}           // sub { time },
        ua            => $args{ua},
        _down         => {},
    }, $class;
    $self->{base_urls} = [ grep {defined} @{ $self->{base_urls} } ];
    die "No valid Obálky base URL configured\n" unless @{ $self->{base_urls} };
    # Test mode (a mock server on dev): its own host may serve images too.
    $self->{extra_hosts} = { map { lc( URI->new($_)->host ) => 1 } grep { !_is_obalky_host( URI->new($_)->host ) } @{ $self->{base_urls} } };
    $self->{ua} //= LWP::UserAgent->new(
        agent        => $self->{user_agent},
        timeout      => $self->{timeout},
        max_redirect => 0,
        protocols_allowed => [ 'http', 'https' ],
    );
    return $self;
}

sub _normalise_base {
    my ( $url, $allow_other ) = @_;
    return unless defined $url;
    $url =~ s/^\s+|\s+$//g;
    $url =~ s{/+$}{};
    my $uri = URI->new($url);
    return unless $uri->scheme && $uri->scheme =~ /^https?$/ && $uri->host;
    return unless $allow_other || _is_obalky_host( $uri->host );
    return $uri->scheme . '://' . lc( $uri->host ) . ( $uri->port == $uri->default_port ? '' : ':' . $uri->port );
}

sub _is_obalky_host {
    my ($host) = @_;
    return defined $host && lc($host) =~ /(?:^|\.)obalkyknih\.cz$/;
}

=head2 normalise_query

    my $q = Koha::Plugin::Cz::ObalkyKnih::Client::normalise_query(
        { isbn => '80-7203-123-X (váz.)', nbn => 'cnb000154538' } );

Returns a clean query hashref for one work, or undef when no usable
identifier is left. ISSN and EAN go into C<isbn>, as Obálky expects.

=cut

sub normalise_query {
    my ($in) = @_;
    return unless ref $in eq 'HASH';
    my %q;

    my @isbns = map { _clean_isbn($_) } map { ref $_ eq 'ARRAY' ? @$_ : $_ } grep {defined} @{$in}{qw( isbn issn ean )};
    @isbns = grep {defined} @isbns;
    # The manual allows an array of ISBNs per work, but the public server code
    # splits a string, so send the first valid one until arrays are confirmed.
    $q{isbn} = $isbns[0] if @isbns;

    if ( defined $in->{nbn} && $in->{nbn} =~ /^\s*(cnb\d{9})\s*$/i ) {
        $q{nbn} = lc $1;
    }
    if ( defined $in->{oclc} && $in->{oclc} =~ /(\d{1,12})/ ) {
        $q{oclc} = "(OCoLC)$1";
    }
    if ( defined $in->{ismn} ) {
        ( my $ismn = uc $in->{ismn} ) =~ s/[^0-9M]//g;
        $q{ismn} = $ismn if $ismn =~ /^(?:M\d{9}|9790\d{9})$/;
    }
    return unless %q;

    for my $part (qw( part_no part_name part_year part_volume )) {
        next unless defined $in->{$part};
        my $v = $in->{$part};
        $v =~ s/[\x00-\x1f]//g;
        $v =~ s/^\s+|\s+$//g;
        $q{$part} = substr( $v, 0, 100 ) if length $v;
    }
    return \%q;
}

sub _clean_isbn {
    my ($raw) = @_;
    return unless defined $raw;
    ( my $s = $raw ) =~ s/^\s+//;
    $s =~ s/[\s(].*$//s;    # drop qualifiers like "(váz.)"
    $s =~ s/[^0-9Xx]//g;
    $s = uc $s;
    return $s if $s =~ /^\d{9}[\dX]$/;     # ISBN-10
    return $s if $s =~ /^\d{13}$/;         # ISBN-13 / EAN / ISMN-13
    return $s if $s =~ /^\d{7}[\dX]$/;     # ISSN
    return;
}

=head2 books

    my $res = $client->books( \@queries, { keywords => 'tolkien' } );

C<@queries> are hashrefs for L</normalise_query>. Returns

    { server => 'https://cache.obalkyknih.cz', items => [ $record_or_undef, ... ] }

with C<items> in the same order as the queries. On failure returns
C<< { error => 'unavailable' | 'not_registered' | 'bad_request', items => [...] } >>.

=cut

sub books {
    my ( $self, $queries ) = @_;
    $queries = [ @$queries[ 0 .. $MAX_BATCH - 1 ] ] if @$queries > $MAX_BATCH;
    my @norm = map { scalar normalise_query($_) } @$queries;
    my @items = (undef) x @norm;

    my ( @todo, @todo_idx );
    for my $i ( 0 .. $#norm ) {
        next unless $norm[$i];
        if ( my $hit = $self->_cache_get( $norm[$i] ) ) {
            $items[$i] = $hit->{none} ? undef : $hit;
            next;
        }
        push @todo,     $norm[$i];
        push @todo_idx, $i;
    }
    return { items => \@items, cached => 1 } unless @todo;

    my $res = $self->_fetch(\@todo);
    return { %$res, items => \@items } if $res->{error};

    my $records = $res->{records};
    my $matched = _pair_records( \@todo, $records );
    for my $j ( 0 .. $#todo ) {
        my $clean = $matched->[$j] ? $self->_sanitise( $matched->[$j], $res->{server} ) : undef;
        $items[ $todo_idx[$j] ] = $clean;
        $self->_cache_set( $todo[$j], $clean // { none => 1 } );
    }
    return { server => $res->{server}, items => \@items };
}

# Obálky leaves unmatched works out of the array, so pair by the echoed
# bibinfo first and fall back to position only when counts line up.
sub _pair_records {
    my ( $queries, $records ) = @_;
    my @out = (undef) x @$queries;
    my %used;
    for my $r ( 0 .. $#$records ) {
        my $rec = $records->[$r];
        next unless ref $rec eq 'HASH';
        my $bib = $rec->{bibinfo};
        next unless ref $bib eq 'HASH';
        for my $q ( 0 .. $#$queries ) {
            next if $out[$q];
            if ( _same_query( $queries->[$q], $bib ) ) {
                $out[$q] = $rec;
                $used{$r} = 1;
                last;
            }
        }
    }
    if ( !%used && @$records == @$queries ) {
        @out = map { ref $_ eq 'HASH' ? $_ : undef } @$records;
    }
    return \@out;
}

sub _same_query {
    my ( $q, $bib ) = @_;
    for my $k (qw( isbn nbn oclc ismn )) {
        next unless defined $q->{$k} && defined $bib->{$k};
        my @a = ref $q->{$k}   eq 'ARRAY' ? @{ $q->{$k} }   : ( $q->{$k} );
        my @b = ref $bib->{$k} eq 'ARRAY' ? @{ $bib->{$k} } : ( $bib->{$k} );
        my %b = map { _canon($_) => 1 } @b;
        return 1 if grep { $b{ _canon($_) } } @a;
    }
    return 0;
}

sub _canon {
    my ($v) = @_;
    $v = lc( $v // '' );
    $v =~ s/[^0-9a-z]//g;
    return $v;
}

sub _sanitise {
    my ( $self, $rec, $server ) = @_;
    my %out;
    for my $f (@URL_FIELDS) {
        my $u = $self->_safe_url( $rec->{$f}, $server ) // next;
        $out{$f} = $u;
    }
    # A record without a backlink must not be shown (Obálky terms).
    return unless $out{backlink_url};
    if ( ref $rec->{annotation} eq 'HASH' && defined $rec->{annotation}{html} ) {
        my $text = _plain_text( $rec->{annotation}{html} );
        if ( length $text ) {
            $out{annotation} = { text => $text };
            my $src = _plain_text( $rec->{annotation}{source} // '' );
            $out{annotation}{source} = $src if length $src;
        }
    }
    for my $dim (qw( orig_width orig_height )) {
        $out{$dim} = 0 + $rec->{$dim} if defined $rec->{$dim} && $rec->{$dim} =~ /^\d{1,5}$/;
    }
    return \%out;
}

sub _safe_url {
    my ( $self, $url, $server ) = @_;
    return unless defined $url && !ref $url && length $url < 1000;
    my $uri = URI->new($url);
    return unless $uri->scheme && $uri->scheme =~ /^https?$/;
    return $uri->as_string if $self->{extra_hosts}{ lc( $uri->host // '' ) };
    return unless _is_obalky_host( $uri->host );
    $uri->scheme('https');
    # Image hosts follow the server that answered, so a failover also moves
    # the browser away from a dead cache server. www.obalkyknih.cz stays.
    if ( $self->{rewrite_host} && $server && lc( $uri->host ) =~ /^cache\d*\.obalkyknih\.cz$/ ) {
        my $srv = URI->new($server);
        $uri->host( $srv->host );
        $uri->port( $srv->port ) if $srv->port != $srv->default_port;
        $uri->scheme( $srv->scheme );
    }
    return $uri->as_string;
}

sub _plain_text {
    my ($s) = @_;
    $s = '' unless defined $s && !ref $s;
    $s =~ s/<[^>]*>//g;
    my %ent = ( amp => '&', lt => '<', gt => '>', quot => '"', apos => "'", nbsp => ' ' );
    $s =~ s/&(amp|lt|gt|quot|apos|nbsp);/$ent{$1}/g;
    $s =~ s/&#(\d{1,6});/chr($1)/ge;
    $s =~ s/&#x([0-9a-fA-F]{1,6});/chr(hex $1)/ge;
    $s =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f]//g;
    $s =~ s/\s+/ /g;
    $s =~ s/^ | $//g;
    return substr( $s, 0, 5000 );
}

sub _fetch {
    my ( $self, $queries ) = @_;
    my $multi = encode_json($queries);
    my $saw_registration_error;

    for my $base ( $self->_servers_in_order ) {
        my $url  = "$base/api/books?multi=" . uri_escape_utf8($multi);
        my $resp = $self->{ua}->get( $url, 'Accept' => 'application/json' );

        if ( $resp->is_success ) {
            my $data = eval { decode_json( $resp->decoded_content // '' ) };
            if ( ref $data eq 'ARRAY' ) {
                return { server => $base, records => $data };
            }
            $self->_mark_down($base);
            next;
        }
        my $code = $resp->code // 0;
        my $body = $resp->decoded_content // '';
        if ( $code == 404 && $body =~ /^\s*\[\s*\]\s*$/ ) {
            return { server => $base, records => [] };
        }
        if ( $code == 404 && $body =~ /sign up|referer/i ) {
            # Registration is shared by all servers; trying others won't help.
            # The body names the IP and referer Obálky saw; show it to admins.
            ( $saw_registration_error = substr( $body, 0, 300 ) ) =~ s/[^\x20-\x7e\x{a0}-\x{17f}]+/ /g;
            last;
        }
        if ( $code == 400 ) {
            return { error => 'bad_request' };
        }
        if ( _is_timeout($resp) && $self->_alive($base) ) {
            # Healthy server, slow first lookup of an uncached record.
            return { error => 'timeout', server => $base };
        }
        $self->_mark_down($base);
    }
    return { error => 'not_registered', detail => $saw_registration_error } if defined $saw_registration_error;
    return { error => 'unavailable' };
}

sub _is_timeout {
    my ($resp) = @_;
    return ( $resp->header('Client-Warning') // '' ) eq 'Internal response'
        && ( $resp->message // '' ) =~ /timeout|timed out/i;
}

sub _alive {
    my ( $self, $base ) = @_;
    my $old  = $self->{ua}->timeout( $self->{alive_timeout} );
    my $resp = $self->{ua}->get("$base/api/runtime/alive");
    $self->{ua}->timeout($old);
    return $resp->is_success && ( $resp->decoded_content // '' ) =~ /^\s*ALIVE\s*$/i;
}

=head2 status

Returns C<< [ { url => ..., alive => 0|1, down_until => epoch|undef }, ... ] >>
for the configuration page.

=cut

sub status {
    my ($self) = @_;
    return [ map { { url => $_, alive => $self->_alive($_) ? 1 : 0, down_until => $self->_down_until($_) } }
            @{ $self->{base_urls} } ];
}

sub _servers_in_order {
    my ($self) = @_;
    my $now  = $self->{now}->();
    my @up   = grep { ( $self->_down_until($_) // 0 ) <= $now } @{ $self->{base_urls} };
    # All servers penalised: try them anyway rather than show nothing forever.
    return @up ? @up : @{ $self->{base_urls} };
}

# Server health is shared across Plack workers through the Koha cache when
# there is one. This caches only server state, never cover data.
sub _down_until {
    my ( $self, $base ) = @_;
    my $key = 'obalkyknih:down:' . $base;
    if ( $self->{cache} ) {
        my $v = $self->{cache}->get_from_cache($key);
        return $v if defined $v;
    }
    return $self->{_down}{$base};
}

sub _mark_down {
    my ( $self, $base ) = @_;
    my $until = $self->{now}->() + $self->{penalty};
    $self->{_down}{$base} = $until;
    $self->{cache}->set_in_cache( 'obalkyknih:down:' . $base, $until, { expiry => $self->{penalty} } )
        if $self->{cache};
}

sub _cache_key {
    my ($q) = @_;
    return 'obalkyknih:books:' . JSON->new->canonical->encode($q);
}

sub _cache_get {
    my ( $self, $q ) = @_;
    return unless $self->{cache} && $self->{cache_ttl} > 0;
    return $self->{cache}->get_from_cache( _cache_key($q) );
}

sub _cache_set {
    my ( $self, $q, $v ) = @_;
    return unless $self->{cache} && $self->{cache_ttl} > 0;
    $self->{cache}->set_in_cache( _cache_key($q), $v, { expiry => $self->{cache_ttl} } );
}

1;
