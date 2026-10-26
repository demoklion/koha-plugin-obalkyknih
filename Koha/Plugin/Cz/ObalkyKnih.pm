package Koha::Plugin::Cz::ObalkyKnih;

# Book covers, annotations and tables of contents from Obálky knih
# (obalkyknih.cz) for the Koha OPAC and staff interface.
#
# Copyright 2026 Ján Dugovič
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.

use Modern::Perl;
use utf8;

use base qw( Koha::Plugins::Base );

use C4::Context;
use JSON qw( decode_json encode_json );
use Try::Tiny;

use Koha::Plugin::Cz::ObalkyKnih::Client;

our $VERSION         = '{VERSION}';
our $MINIMUM_VERSION = '{MINIMUM_VERSION}';

our $metadata = {
    name            => 'Obálky knih',
    author          => 'Ján Dugovič',
    date_authored   => '2026-10-26',
    date_updated    => '1900-01-01',
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Book covers, annotations and tables of contents from Obálky knih (obalkyknih.cz). '
        . 'Obálky, anotace a obsahy knih ze služby Obálky knih.',
    namespace       => 'obalkyknih',
};

our %DEFAULTS = (
    enable_opac     => 1,
    enable_staff    => 1,
    base_urls       => join( "\n", @Koha::Plugin::Cz::ObalkyKnih::Client::DEFAULT_BASE_URLS ),
    size_results    => 'medium',
    size_detail     => 'medium',
    show_annotation => 1,
    show_toc        => 1,
    local_wins      => 1,
    cache_ttl       => 0,
    timeout         => 6,
    sigla           => '',
    test_mode       => 0,
);

our @SIZES = qw( icon medium preview510 );

sub new {
    my ( $class, $args ) = @_;
    $args->{metadata} = $metadata;
    $args->{metadata}->{class} = $class;
    return $class->SUPER::new($args);
}

sub install {
    my ($self) = @_;
    my %data = map { $_ => $DEFAULTS{$_} } grep { !defined $self->retrieve_data($_) } keys %DEFAULTS;
    $self->store_data( \%data ) if %data;
    return 1;
}

sub upgrade {
    my ($self) = @_;
    return $self->install;
}

sub uninstall { return 1 }

=head2 setting

    my $v = $plugin->setting('cache_ttl');

Stored value, or the default.

=cut

sub setting {
    my ( $self, $key ) = @_;
    my $v = $self->retrieve_data($key);
    return defined $v && $v ne '' ? $v : $DEFAULTS{$key};
}

=head2 client

Returns a L<Koha::Plugin::Cz::ObalkyKnih::Client> built from the settings.

=cut

sub client {
    my ($self) = @_;
    my $cache;
    try {
        require Koha::Caches;
        $cache = Koha::Caches->get_instance;
    };
    return Koha::Plugin::Cz::ObalkyKnih::Client->new(
        base_urls         => [ grep {/\S/} split /\s*[\r\n]+\s*/, $self->setting('base_urls') ],
        timeout           => $self->setting('timeout'),
        cache             => $cache,
        cache_ttl         => $self->setting('cache_ttl'),
        allow_other_hosts => $self->setting('test_mode'),
        user_agent        => "koha-plugin-obalkyknih/$VERSION (Koha " . ( C4::Context->preference('Version') // '?' ) . ')',
    );
}

# ---------------------------------------------------------------- configure

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{cgi};
    my $op  = $cgi->param('op') // '';

    if ( $op eq 'cud-save' ) {
        my %in;
        $in{$_} = $cgi->param($_) ? 1 : 0 for qw( enable_opac enable_staff show_annotation show_toc local_wins test_mode );
        for my $size (qw( size_results size_detail )) {
            my $v = $cgi->param($size) // '';
            $in{$size} = ( grep { $_ eq $v } @SIZES ) ? $v : $DEFAULTS{$size};
        }
        my $ttl = $cgi->param('cache_ttl') // 0;
        $in{cache_ttl} = $ttl =~ /^\d{1,5}$/ ? $ttl : 0;
        my $timeout = $cgi->param('timeout') // '';
        $in{timeout} = $timeout =~ /^\d{1,2}$/ && $timeout >= 1 ? $timeout : $DEFAULTS{timeout};
        my $sigla = uc( $cgi->param('sigla') // '' );
        $in{sigla} = $sigla =~ /^[A-Z]{3}\d{3}$/ ? $sigla : '';

        my @urls = grep {/\S/} split /\s*[\r\n]+\s*/, ( $cgi->param('base_urls') // '' );
        my @valid = grep {defined} map { Koha::Plugin::Cz::ObalkyKnih::Client::_normalise_base( $_, $in{test_mode} ) } @urls;
        $in{base_urls} = @valid ? join( "\n", @valid ) : $DEFAULTS{base_urls};

        $self->store_data( \%in );
        print $cgi->redirect( '/cgi-bin/koha/plugins/run.pl?class=' . ref($self) . '&method=configure&saved=1' );
        return;
    }

    my $template = $self->get_template( { file => 'templates/configure.tt' } );
    $template->param( map { $_ => $self->setting($_) } keys %DEFAULTS );
    $template->param(
        saved   => scalar $cgi->param('saved'),
        sizes   => \@SIZES,
        version => $VERSION,
    );

    if ( $op eq 'check' ) {
        my $client = $self->client;
        my $probe  = $client->books( [ { isbn => '9788074151330' } ] );
        $template->param(
            checked      => 1,
            servers      => [
                map { { %$_, down_until => $_->{down_until} && $_->{down_until} > time ? scalar localtime( $_->{down_until} ) : undef } }
                    @{ $client->status }
            ],
            probe_error  => $probe->{error},
            probe_detail => $probe->{detail},
            probe_server => $probe->{server},
            probe_cover  => ( $probe->{items}[0] // {} )->{cover_medium_url},
        );
    }
    $self->output_html( $template->output );
    return;
}

# ------------------------------------------------------------------ routes

sub api_namespace { return $metadata->{namespace} }

sub api_routes {
    my ($self) = @_;
    return decode_json( $self->mbf_read('openapi.json') );
}

sub static_routes {
    my ($self) = @_;
    return decode_json( $self->mbf_read('staticapi.json') );
}

# ------------------------------------------------------------------- hooks

# Koha renders the cover column only when a cover plugin returns something,
# so these return a marker; the real work is in the script from *_js.
sub opac_cover_images {
    my ($self) = @_;
    return eval { $self->setting('enable_opac') } ? "<!-- Obálky knih -->" : q{};
}

sub intranet_cover_images {
    my ($self) = @_;
    return eval { $self->setting('enable_staff') } ? "<!-- Obálky knih -->" : q{};
}

sub opac_head {
    my ($self) = @_;
    return q{} unless $self->setting('enable_opac');
    return $self->_css_tag;
}

sub intranet_head {
    my ($self) = @_;
    return q{} unless $self->setting('enable_staff');
    return $self->_css_tag;
}

sub opac_js {
    my ($self) = @_;
    return q{} unless $self->setting('enable_opac');
    return $self->_script_tag('opac');
}

sub intranet_js {
    my ($self) = @_;
    return q{} unless $self->setting('enable_staff');
    return $self->_script_tag('staff');
}

sub _static_url {
    my ( $self, $path ) = @_;
    return '/api/v1/contrib/' . $self->api_namespace . "/static/$path?v=" . _attr($VERSION);
}

sub _css_tag {
    my ($self) = @_;
    return '<link rel="stylesheet" href="' . $self->_static_url('css/obalkyknih.css') . '">';
}

sub _script_tag {
    my ( $self, $interface ) = @_;
    my $config = {
        api            => '/api/v1/contrib/' . $self->api_namespace . '/covers',
        interface      => $interface,
        sizeResults    => $self->setting('size_results'),
        sizeDetail     => $self->setting('size_detail'),
        showAnnotation => $self->setting('show_annotation') ? JSON::true : JSON::false,
        showToc        => $self->setting('show_toc')        ? JSON::true : JSON::false,
        localWins      => $self->setting('local_wins')      ? JSON::true : JSON::false,
        sigla          => $self->setting('sigla'),
    };
    return '<script src="'
        . $self->_static_url('js/obalkyknih.js')
        . '" data-obalkyknih-config="'
        . _attr( JSON->new->canonical->encode($config) )
        . '"></script>';
}

sub _attr {
    my ($s) = @_;
    $s //= '';
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    $s =~ s/'/&#39;/g;
    return $s;
}

1;
