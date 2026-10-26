use strict;
use warnings;
use utf8;
use open qw( :std :encoding(UTF-8) );

use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/..";

use Test::More;

use Koha::Plugin::Cz::ObalkyKnih::Identifiers;

# Just enough of MARC::Record / MARC::Field for from_marc().
{
    package FakeField;
    sub new { my ( $c, $tag, $i1, %sf ) = @_; bless { tag => $tag, i1 => $i1, sf => \%sf }, $c }
    sub indicator { $_[0]{i1} }
    sub subfield  { $_[0]{sf}{ $_[1] } }

    package FakeRecord;
    sub new { my ( $c, @f ) = @_; bless { f => \@f }, $c }
    sub field { my ( $s, $tag ) = @_; my @m = grep { $_->{tag} eq $tag } @{ $s->{f} }; wantarray ? @m : $m[0] }
}

sub from { Koha::Plugin::Cz::ObalkyKnih::Identifiers::from_marc( FakeRecord->new(@_) ) }

is_deeply from(
    FakeField->new( '020', ' ', a => '978-80-7415-133-0 (váz.)' ),
    FakeField->new( '020', ' ', a => '80-7203-123-X' ),
    FakeField->new( '015', ' ', a => 'cnb002840948' ),
    FakeField->new( '035', ' ', a => '(OCoLC)ocm311597120' ),
    FakeField->new( '245', '1', a => 'Pán prstenů.', n => 'Díl 2,', p => 'Dvě věže /' ),
),
    {
    isbn      => '9788074151330',
    nbn       => 'cnb002840948',
    oclc      => '(OCoLC)311597120',
    part_no   => 'Díl 2',
    part_name => 'Dvě věže',
    },
    'monograph with ISBN, ČNB, OCLC and part';

is_deeply from( FakeField->new( '022', ' ', a => '1210-8510' ) ), { isbn => '12108510' }, 'ISSN';

is_deeply from( FakeField->new( '024', '2', a => '979-0-2600-0043-8' ), FakeField->new( '024', '3', a => '8594030000013' ) ),
    { isbn => '8594030000013', ismn => '9790260000438' }, 'ISMN and EAN from 024';

is_deeply from( FakeField->new( '015', ' ', a => 'cnb000154538' ) ), { nbn => 'cnb000154538' }, 'ČNB only';

is from( FakeField->new( '245', '0', a => 'Bez identifikátorů' ) ), undef, 'no identifiers gives undef';

done_testing;
