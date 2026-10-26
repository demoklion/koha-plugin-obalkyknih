package Koha::Plugin::Cz::ObalkyKnih::Identifiers;

# Builds an Obálky query (isbn, nbn, oclc, ismn, part_*) from a MARC record.
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

use Koha::Plugin::Cz::ObalkyKnih::Client;

=head1 NAME

Koha::Plugin::Cz::ObalkyKnih::Identifiers - identifiers for Obálky from MARC 21

=head1 SYNOPSIS

    my $query = Koha::Plugin::Cz::ObalkyKnih::Identifiers::from_marc($record);

=head1 DESCRIPTION

Reads MARC 21 bibliographic fields:

    020 $a  ISBN            022 $a  ISSN
    024 $a  ISMN/EAN (ind1 2 = ISMN, 3 = EAN)
    015 $a  national bibliography number (ČNB, "cnb...")
    035 $a  "(OCoLC)..."    245 $n $p  part number / part name

Returns a hashref ready for
L<Koha::Plugin::Cz::ObalkyKnih::Client/normalise_query>, or undef.

=cut

sub from_marc {
    my ($record) = @_;
    return unless $record;
    my %q;

    my @isbn = _subfields( $record, '020', 'a' );
    push @isbn, _subfields( $record, '022', 'a' );
    for my $f ( $record->field('024') ) {
        my $ind1 = $f->indicator(1) // '';
        my $v    = $f->subfield('a') // next;
        if ( $ind1 eq '2' ) { $q{ismn} //= $v }
        elsif ( $ind1 eq '3' ) { push @isbn, $v }
    }
    $q{isbn} = \@isbn if @isbn;

    for my $v ( _subfields( $record, '015', 'a' ) ) {
        if ( $v =~ /^\s*(cnb\d{9})/i ) { $q{nbn} = $1; last }
    }
    for my $v ( _subfields( $record, '035', 'a' ) ) {
        if ( $v =~ /^\s*\(OCoLC\)\s*(?:oc[mn]|on)?(\d+)/i ) { $q{oclc} = $1; last }
    }

    if ( my $f245 = $record->field('245') ) {
        my $n = $f245->subfield('n');
        my $p = $f245->subfield('p');
        $q{part_no}   = _trim_punct($n) if defined $n;
        $q{part_name} = _trim_punct($p) if defined $p;
    }

    return Koha::Plugin::Cz::ObalkyKnih::Client::normalise_query( \%q );
}

sub _subfields {
    my ( $record, $tag, $code ) = @_;
    return grep { defined && length } map { $_->subfield($code) } $record->field($tag);
}

sub _trim_punct {
    my ($s) = @_;
    $s =~ s/^\s+//;
    $s =~ s/[\s.,:;\/=]+$//;
    return $s;
}

1;
