package TeX::Patterns;

use strict;
use warnings;

use version; our $VERSION = qv '1.3.0';

use base qw(Exporter);

## Exported scalars must be package variables, *not* lexical variables!

our %EXPORT_TAGS = (all => [ qw($BALANCED_TEXT) ]);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{all} },
                   qw($ARGUMENT_TOKEN
                      $CONTROL_SEQUENCE
                      $CONTROL_SYMBOL
                      $CONTROL_WORD
                      $LETTER
                      $NON_LETTER
                      $OPT_ARG
                      $PARENTHESIZED_ARG
                      $TEXT_CHAR)
    );

our @EXPORT;

our $NULL_CHAR = "\x00";
our $EOL_MARK  = "\x7F";

## CATCODE CATEGORIES

our $ESCAPE      = qr{\\};                               #  0
our $BEGIN_GROUP = qr/\{/;                               #  1
our $END_GROUP   = qr/\}/;                               #  2
our $MATH_SHIFT  = qr{\$};                               #  3
our $ALIGNMENT   = qr{&};                                #  4
our $END_OF_LINE = qr{\r};                               #  5
our $PARAMETER   = qr{\#};                               #  6
our $SUPERSCRIPT = qr{[\^]};                             #  7
our $SUBSCRIPT   = qr{_};                                #  8
our $IGNORED     = qr{\x7F};                             #  9 [*]
our $SPACE       = qr{[ \t]};                            # 10
our $LETTER      = qr{(?: [a-zA-Z] )}smx;                # 11
our $OTHER       = qr{[\n!\"\'-\@\[\]\`|\x80-\xFF]};     # 12
our $ACTIVE      = qr{[~\f]};                            # 13
our $COMMENT     = qr{[%]};                              # 14
our $INVALID     = qr{[\x01-\x08\x0B\x0E-\x1F\x7F]};     # 15 [**]

## [*] Unlike plain TeX, in LaTeX, DEL (\x7F) is actually INVALID, not
## IGNORED and, in fact, there are no IGNORED characters in LaTeX.
## However, it would be pedagogically awkward to have $IGNORED be the
## null pattern, so in a petulant attempt to have my cake and eat it
## too, I've listed DEL as both IGNORED and INVALID.  In input_line,
## I'll process $INVALID first, so this will have no effect on the
## output of the parser.

## [**] NUL is not here.

## These are the characters that can appear as control symbol names.

our $NON_LETTER  = qr{
    (?: $ESCAPE | $BEGIN_GROUP | $END_GROUP | $MATH_SHIFT
     | $ALIGNMENT | $PARAMETER | $SUPERSCRIPT | $SUBSCRIPT
     | $SPACE | $OTHER | $ACTIVE | $COMMENT )
}smx;

our $TEXT_CHAR        = qr{ (?: $SPACE | $LETTER | $OTHER ) }smx;

our $CONTROL_WORD     = qr{ $ESCAPE (?: $LETTER+ ) }smx;

our $CONTROL_SYMBOL   = qr{ $ESCAPE (?: $NON_LETTER ) }smx;

our $CONTROL_SEQUENCE = qr{ (?: $CONTROL_SYMBOL | $CONTROL_WORD ) }smx;

our $ARGUMENT_TOKEN   = qr{ (?: $CONTROL_SEQUENCE | $TEXT_CHAR ) }smx;

our $BALANCED_TEXT;

{
    use re 'eval';

    $BALANCED_TEXT = qr{
        (?> [^{}]+ | \{ (??{ $BALANCED_TEXT }) \} | $CONTROL_SEQUENCE )*
    }smx;
}

our $OPT_ARG = qr{
    (?: \[ (?: $CONTROL_SEQUENCE | [^\[\]{}]+ | \{ $BALANCED_TEXT \} )+ \] )
}smx;

our $PARENTHESIZED_ARG = qr{
    (?: \( (?: $CONTROL_SEQUENCE | [^\(\){}]+ | \{ $BALANCED_TEXT \} )+ \) )
}smx;

1;

__END__
