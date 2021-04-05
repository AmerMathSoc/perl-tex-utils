package TeX::TeX2MML;

use strict;
use warnings;

use version; our $VERSION = qv '0.0.0';

use Carp;

use base qw(Exporter);

our %EXPORT_TAGS = (all => [ qw(tex2mml) ]);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{all} } );

our @EXPORT = @EXPORT_OK;

sub tex2mml( $;$ ) {
    croak "Sorry, this isn't ready for distribution yet.";
}

1;

__END__
