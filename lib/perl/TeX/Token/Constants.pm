package TeX::Token::Constants;

use strict;
use warnings;

use version; our $VERSION = qv '1.0.0';

use base qw(Exporter);

our %EXPORT_TAGS = (all => [ qw(BEGIN_GROUP END_GROUP
                                BEGIN_OPT   END_OPT   OPT_ARG
                                STAR) ] );

our @EXPORT_OK = @{ $EXPORT_TAGS{all} };

our @EXPORT = qw();

use TeX::Token qw(:factories);
use TeX::WEB2C qw(:catcodes);

use constant {
    BEGIN_GROUP => make_character_token('{', CATCODE_BEGIN_GROUP),
    END_GROUP   => make_character_token('}', CATCODE_END_GROUP)
};

use constant {
    BEGIN_OPT => make_character_token('[', CATCODE_OTHER),
    END_OPT   => make_character_token(']', CATCODE_OTHER),
};

use constant {
    OPT_ARG   => [ BEGIN_OPT, make_param_ref_token(1), END_OPT],
};

use constant {
    STAR => make_character_token('*', CATCODE_OTHER),
};

1;

__END__
