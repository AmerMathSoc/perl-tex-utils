package TeX::Simple::HTML;

use strict;
use warnings;

use version; our $VERSION = qv '1.1.0';

use base qw(Exporter);

our %EXPORT_TAGS = (all => [ qw(tex_to_html) ]);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{all} } );

our @EXPORT = @EXPORT_OK;

######################################################################
##                                                                  ##
##                             IMPORTS                              ##
##                                                                  ##
######################################################################

use TeX::Utils::Misc;

use TeX::Simple::JPTS;

######################################################################
##                                                                  ##
##                             LOGGING                              ##
##                                                                  ##
######################################################################

use TeX::Logger;

my $LOG = TeX::Logger->get_logger();

## Avoid finalization segfault.
END { undef $LOG };

######################################################################
##                                                                  ##
##                            CONSTANTS                             ##
##                                                                  ##
######################################################################

my $HTML_DECL = << 'EOF';
<!DOCTYPE html>

<html>
<head>
<meta charset='utf-8'>
<script type="text/x-mathjax-config">
MathJax.Hub.Config({
  tex2jax: {inlineMath: [['$','$'], ['\\(','\\)']]}
});
</script>
<script type="text/javascript" async
  src="https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-MML-AM_CHTML">
</script>
</head>

EOF

######################################################################
##                                                                  ##
##                             EXPORTED                             ##
##                                                                  ##
######################################################################

my %HTML_TAG = (italic       => 'em',
                bold         => 'strong',
                monospace    => 'code',
                sc           => [ span => 'style="font-variant: small-caps"' ],
                roman        => [ span => 'style="font-style: normal"' ],
                'sans-serif' => [ span => 'style="font-family: sans-serif"' ],
                underline    => 'u',
                'list-item'  => 'li',
                'disp-quote' => 'blockquote',
                'ref-list'   => 'ul',
                ref          => 'li',
);

sub replace_tag( $$ ) {
    my $end = shift;
    my $tag = shift;

    my $repl = $HTML_TAG{$tag};

    return $tag unless defined $repl;

    if (ref($repl)) {
        my ($tag, $att) = @{ $repl };

        if (defined $end) {
            return $tag;
        } else {
            return "$tag $att";
        }
    }

    return $repl;
}

sub tex_to_html( $;$ ) {
    my $tex_string = shift;

    return "" unless nonempty($tex_string);

    my %opts = (mathml => 0);

    if (defined $_[0] && ref($_[0]) eq 'HASH') {
        %opts = (%opts, %{ $_[0] });
    }

    my $xml = TeX::Simple::JPTS::__tex_to_jpts($tex_string, \%opts);

    # Simple and inelegant will do for now.

    $xml =~ s{<\?xml\s.*?\?>\s*}{}smx;

    $xml =~ s{<!DOCTYPE\s.*?>\s*}{$HTML_DECL}smx;

    $xml =~ s{(</?p>\s*)*<article xml:lang.*?>\s*(</p>)?}{<body>\n\n};

    $xml =~ s{(<p>)?</article>}{</body>\n</html>\n};

    $xml =~ s{ < (/?) \K ([\w-]+) (?=>) }{ replace_tag($1, $2) }esmxg;

    $xml =~ s{<ext-link \s* xlink:href="(.*?)">(.*?)</ext-link>}
             {<a href="$1">$2</a>}gsmx;

    $xml =~ s{<inline-formula.*?>\s*<tex-math>\s*}{\$}g;
    $xml =~ s{\s*</tex-math>\s*</inline-formula>}{\$}g;

    $xml =~ s{<disp-formula.*?>\s*<tex-math>\s*}{}g;
    $xml =~ s{\s*</tex-math>\s*</disp-formula>}{}g;

    $xml =~ s{<list list-type="order">}{<ol>}g;
    $xml =~ s{</list list-type="order">}{</ol>}g;

    $xml =~ s{<element-citation>.*?</element-citation>}{}smxg;

    $xml =~ s{</?citation-alternatives>}{}g;
    $xml =~ s{</?mixed-citation>}{}g;

    ## See comments in TeX::Simple::JPTS::make_end_list_handler

    $xml =~ s{<list list-type="bullet">}{<ul>}g;
    $xml =~ s{</list list-type="bullet">}{</ul>}g;

    return $xml;
}

1;

__END__
