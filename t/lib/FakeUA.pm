package FakeUA;

# A stand-in for LWP::UserAgent that answers from a routing table and records
# every request, so client tests never touch the network.

use strict;
use warnings;

use HTTP::Response;
use URI;
use URI::QueryParam;

sub new {
    my ( $class, %routes ) = @_;
    return bless { routes => \%routes, log => [], timeout => 6 }, $class;
}

sub timeout {
    my ( $self, $t ) = @_;
    my $old = $self->{timeout};
    $self->{timeout} = $t if defined $t;
    return $old;
}

sub requests { @{ $_[0]{log} } }

sub get {
    my ( $self, $url ) = @_;
    push @{ $self->{log} }, $url;
    my $uri  = URI->new($url);
    my $key  = $uri->host . $uri->path;
    my $spec = $self->{routes}{$key} // [ 500, 'no route' ];
    $spec = $spec->( $uri, $self ) if ref $spec eq 'CODE';
    my ( $code, $body, $headers ) = @$spec;
    my $resp = HTTP::Response->new( $code, $code == 500 && $headers && $headers->{timeout} ? 'read timeout' : 'X' );
    $resp->content($body) if defined $body;
    $resp->header( 'Content-Type' => 'application/json; charset=utf-8' );
    $resp->header( 'Client-Warning' => 'Internal response' ) if $headers && $headers->{timeout};
    return $resp;
}

package FakeCache;

sub new { bless { data => {} }, shift }
sub get_from_cache { $_[0]{data}{ $_[1] } }
sub set_in_cache { $_[0]{data}{ $_[1] } = $_[2] }

1;
