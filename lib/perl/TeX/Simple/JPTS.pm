package TeX::Simple::JPTS;

use strict;
use warnings;

use version; our $VERSION = qv '1.10.0';

use base qw(Exporter);

our %EXPORT_TAGS = (all => [ qw(tex_to_jpts) ]);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{all} } );

our @EXPORT = @EXPORT_OK;

######################################################################
##                                                                  ##
##                             IMPORTS                              ##
##                                                                  ##
######################################################################

use Carp;

use TeX::Utils::DOI;

use TeX::Utils::Misc;

use Scalar::Util qw(refaddr);

use TeX::AMSrefs;
use TeX::AMSrefs::JPTS;
use TeX::AMSrefs::BibItem;

use TeX::Patterns qw(:all);

use TeX::Token qw(:factories :constants);

# use TeX::Token::Constants qw(:all);

use TeX::WEB2C qw(:catcodes);

use TeX::TeX2MML;

use TeX::Parser::LaTeX;

use PTG::Unicode::Translators;

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
##                        PACKAGE CONSTANTS                         ##
##                                                                  ##
######################################################################

my %ENV_TO_TAG = ();

use constant {
    END_TOKEN          => make_csname_token('end'),
    BEGIN_INLINE_MATH  => make_csname_token('('),
    END_INLINE_MATH    => make_csname_token(')'),
    BEGIN_DISPLAY_MATH => make_csname_token('['),
    END_DISPLAY_MATH   => make_csname_token(']'),
};

######################################################################
##                                                                  ##
##                           INNER CLASS                            ##
##                                                                  ##
######################################################################

{ package Output_State;

  use PTG::Class;

  my %list_ctr_of :COUNTER(:name<list_ctr> :default<0>);

  # 0 outside of list; 1 beginning of list; 2 mid-item
  my %list_state_of :COUNTER(:name<list_state> :default<0>);

  my %generate_mathml_of :ATTR(:name<generate_mathml> :default<0>);

  my %amsrefs_tex_of  :ATTR(:name<amsrefs_tex>);
  my %amsrefs_jpts_of :ATTR(:name<amsrefs_jpts>);

  my %output_buffer_of :ATTR(:name<output_buffer>);

  my %par_tag_of :ATTR(:name<par_tag> :default<"p">);

  my %in_bibitem_of :BOOLEAN(:name<in_bibitem> :default<0>);

  sub output {
      my $self = shift;

      my $text = shift;

      $output_buffer_of{ident $self} .= $text;

      return;
  }
}

######################################################################
##                                                                  ##
##                             EXPORTED                             ##
##                                                                  ##
######################################################################

sub tex_to_jpts( $;$ ) {
    my $tex_string = shift;
    my $opt = shift;

    ## See make_end_list_handler for an explanation of this silliness.

    my $jpts = __tex_to_jpts($tex_string, $opt);

    $jpts =~ s{</list .*?>}{</list>}g;

    return $jpts;
}

sub __tex_to_jpts( $;$ ) {
    my $tex_string = shift;

    return "" unless nonempty($tex_string);

    my %opts = (mathml => 1);

    if (defined $_[0] && ref($_[0]) eq 'HASH') {
        %opts = (%opts, %{ $_[0] });
    }

    $tex_string = __normalize($tex_string);

    my $output = Output_State->new({ amsrefs_tex  => TeX::AMSrefs->new(),
                                     amsrefs_jpts => TeX::AMSrefs::JPTS->new(),
                                     generate_mathml => $opts{mathml},
                                   });

    my $parser = __get_tex_parser($output, \%opts);

    $parser->bind_to_string($tex_string);

    $parser->parse();

    if ($parser->math_nesting() > 0) {
        $LOG->warning("Unbalanced math delimiters in '$tex_string'\n");

        while ($parser->math_nesting() > 0) {
            do_math_shift_off($parser, undef);
        }
    }

    my $output_buffer = $output->get_output_buffer();

    if (defined $output_buffer) {
        $output =~ s/\s+ \z//smx; # delete possible end_line_char space
    }

    return "" if empty $output_buffer;

    return $output_buffer;
}

######################################################################
##                                                                  ##
##                            UTILITIES                             ##
##                                                                  ##
######################################################################

sub __normalize( $ ) {
    my $tex_string = shift;

    $tex_string = PTG::Unicode::Translators::__do_tex_ligs($tex_string);

    $tex_string =~ s{\{\\em\s+}{\\emph\{}g;
    $tex_string =~ s{\{\\bf(series)?\s+}{\\textbf\{}g;
    $tex_string =~ s{\{\\it(shape)?\s+}{\\textit\{}g;
    $tex_string =~ s{\{\\rm\s+}{\\textrm\{}g;
    $tex_string =~ s{\{\\sc(shape)?\s+}{\\textsc\{}g;
    $tex_string =~ s{\{\\tt\s+}{\\texttt\{}g;
    $tex_string =~ s{\{\\sf\s+}{\\textsf\{}g;
    $tex_string =~ s{\{\\sl\s+}{\\textsl\{}g;
    $tex_string =~ s{\{\\upshape\s+}{\\textup\{}g;

    $tex_string =~ s{\\sp\b}{^}g;
    $tex_string =~ s{\\sb\b}{_}g;

    return $tex_string;
}

######################################################################
##                                                                  ##
##                            THE PARSER                            ##
##                                                                  ##
######################################################################

sub __get_tex_parser($;$) {
    my $output = shift;

    my $opts = shift || {}; ## UNUSED AT PRESENT

    my $parser = TeX::Parser::LaTeX->new( { encoding => 'utf8',
                                            buffer_output => 1, });

    PTG::Unicode::Translators::__add_standard_handlers($parser);

    $parser->set_handler(documentclass => make_documentclass_handler($output));

    $parser->set_handler(begin => make_begin_handler($output));
    $parser->set_handler(end   => make_end_handler($output));

    $parser->set_handler(usepackage => \&gobble);

    $parser->let(nofiles     => '@empty');
    $parser->let(nobreakdash => '@empty');
    $parser->let(allowbreak  => '@empty');

    $parser->set_handler(document => make_document_handler($output));
    $parser->set_handler(enddocument => make_enddocument_handler($output));

    $parser->set_handler(abstract => make_abstract_handler($output));
    $parser->set_handler(endabstract => make_endabstract_handler($output));

    $parser->set_handler(openXMLelement  => \&do_openXMLelement);
    $parser->set_handler(closeXMLelement => \&do_closeXMLelement);

    { my $math_env_handler = make_math_env_handler($output);

      for my $env (qw(align align* alignat alignat* displaymath eqnarray eqnarray* equation equation* gather gather* multline multline*)) {
          $parser->set_handler($env => $math_env_handler);
      }
    }

    $parser->set_handler(enumerate => make_list_handler($output, 'order'));
    $parser->set_handler(itemize   => make_list_handler($output, 'bullet'));

    $parser->set_handler(endenumerate => make_end_list_handler($output, 'order'));
    $parser->set_handler(enditemize   => make_end_list_handler($output, 'bullet'));

    $parser->set_handler(quote    => make_quote_handler($output));
    $parser->set_handler(endquote => make_endquote_handler($output));

    $parser->set_handler(item => make_item_handler($output));

    $parser->set_handler(bysame => \&do_bysame);
    $parser->set_handler(MR     => \&do_MR);

    $parser->set_handler(PrintDOI => \&do_PrintDOI);
    $parser->set_handler(arXiv  => \&do_arXiv);
    $parser->set_handler(url    => \&do_url);
    $parser->set_handler(href   => \&do_href);

    $parser->set_handler(q{&} => \&do_ampersand);
    $parser->set_handler(ndash => \&do_ndash);

    $parser->set_handler(tsub => \&do_tsub);
    $parser->set_handler(tsup => \&do_tsub);

    $parser->let(textsuperscript => 'tsup');

    for my $bib (qw(chapter div section)) {
        $parser->let("bib${bib}"    => '@empty');
        $parser->let("endbib${bib}" => '@empty');
    }

    $parser->set_handler(biblist    => make_biblist_handler($output));

    $parser->set_handler(endbiblist => make_endbiblist_handler($output));

    $parser->set_handler(bib     => make_bib_handler($output));
    $parser->set_handler(bibitem => make_bibitem_handler($output));

    $parser->set_handler(issuetext => \&do_issuetext);

    $parser->let(eprintpages => '@firstofone');

    $parser->set_comment_handler(\&gobble);

    { my $math_shift_handler = make_math_shift_handler($output);
      $parser->set_handler('(' => $math_shift_handler);
      $parser->set_handler('[' => $math_shift_handler);
      $parser->set_math_shift_handler($math_shift_handler);
    }

    $parser->set_handler(emph   => make_font_style("italic", "toggle='yes'"));
    $parser->set_handler(textup => make_font_style("roman"));
    $parser->set_handler(textbf => make_font_style("bold"));
    $parser->set_handler(textit => make_font_style("italic"));
    $parser->set_handler(texttt => make_font_style("monospace"));
    $parser->set_handler(textsc => make_font_style("sc"));
    $parser->set_handler(textsf => make_font_style("sans-serif"));
    $parser->set_handler(textsl => make_font_style("italic"));
    $parser->set_handler(textrm => make_font_style("roman"));
    $parser->let(textnormal => '@firstofone');

    $parser->set_handler(underline => make_font_style("underline"));

    # $parser->set_csname_handler(make_csname_handler($output));

    $parser->set_default_handler(\&default_handler);

    $parser->set_handler(par => make_par_handler($output));

    return $parser;
}

######################################################################
##                                                                  ##
##                             HANDLERS                             ##
##                                                                  ##
######################################################################

sub orphan {
    my $parser = shift;
    my $token = shift;

    $LOG->warn("Orphaned $token\n");

    return;
}

sub gobble {
    my $parser = shift;
    my $token = shift;

    $parser->read_undelimited_parameter();

    return;
}

sub do_bysame {
    my $parser = shift;
    my $token = shift;

    $parser->default_handler("---");

    return;
}

sub do_MR {
    my $parser = shift;
    my $token = shift;

    my $mr_num = $parser->read_undelimited_parameter();

    $mr_num =~ s{^\s*MR\s*}{};

    my $text = " MR <bold>$mr_num</bold>";

    my ($cno) = split /\s+/, $mr_num;

    if (defined($cno) && length($cno)) {
        my $url = qq{https://www.ams.org/mathscinet-getitem?mr=$cno};

        $text = qq{<ext-link xlink:href="$url">$text</ext-link>};
    }

    $parser->default_handler($text);

    return;
}

sub do_arXiv {
    my $parser = shift;
    my $token = shift;

    my $arg = $parser->read_undelimited_parameter();

    $parser->default_handler(" arXiv:$arg");

    return;
}

sub do_PrintDOI {
    my $parser = shift;
    my $token = shift;

    my $doi = $parser->read_undelimited_parameter();

    my $display_doi = xml_encode($doi);

    my $url_doi = $doi;

    if ($url_doi !~ m{\A http:}smx) {
        $url_doi = doi_to_url($doi);
    }

    $url_doi = xml_encode($url_doi);

    $parser->default_handler(qq{ DOI <ext-link xlink:href="$url_doi">$display_doi</ext-link});

    return;
}

sub do_url ( $ ) {
    my $parser = shift;
    my $token = shift;

    $parser->save_catcodes();

    $parser->set_catcode(ord('~'), CATCODE_OTHER);

    my $raw_url = $parser->read_undelimited_parameter();

    my $url = $parser->expand_string($raw_url);

    $parser->restore_catcodes();

    $parser->default_handler(qq{<ext-link xlink:href="$url">$url</ext-link>});

    return;
}

sub do_href ( $ ) {
    my $parser = shift;
    my $token = shift;

    my $raw_url = $parser->read_undelimited_parameter();
    my $raw_text = $parser->read_undelimited_parameter();

    my $url  = $parser->expand_string($raw_url);
    my $text = $parser->expand_string($raw_text);

    $parser->default_handler(qq{<ext-link xlink:href="$url">$text</ext-link>});

    return;
}

sub do_ampersand {
    my $parser = shift;
    my $token = shift;

    $parser->default_handler('&amp;');

    return;
}

sub do_ndash {
    my $parser = shift;
    my $token = shift;

    $parser->default_handler("\x{2013}");

    return;
}

sub do_tsub ( $ ) {
    my $parser = shift;
    my $token = shift;

    my $arg = $parser->read_undelimited_parameter();

    my $script = $parser->expand_string($arg);

    my $tag = { tsup => 'sup', tsub => 'sub', textsuperscript => 'sup'}->{$token->get_csname()};

    $parser->default_handler(qq{<$tag>$script</$tag>});

    return;
}

# sub make_csname_handler( $ ) {
#     my $output = shift;
#
#     return sub {
#         my $parser = shift;
#         my $token = shift;
#
#         $parser->default_handler($token);
#
#         $LOG->notify("Unknown LaTeX command: $token\n");
#
#         return;
#     };
# }

sub make_font_style ( $ ) {
    my $tag = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        my $arg = $parser->read_undelimited_parameter();

        my $processed_arg = $parser->expand_string($arg);

        $parser->default_handler("<$tag>");

        $parser->default_handler($processed_arg);

        $parser->default_handler("</$tag>");

        return;
    };
}

sub make_math_shift_handler( $$ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        my $tag           = 'inline-formula';
        my $content_type  = "math/tex";
        my $inner_tag     = 'tex-math';
        my $double_dollar = 0;

        my $end_token = $token;

        if (refaddr($token) == refaddr(BEGIN_INLINE_MATH)) {
            $end_token = END_INLINE_MATH;
        } elsif (refaddr($token) == refaddr(BEGIN_DISPLAY_MATH)) {
            $end_token = END_DISPLAY_MATH;

            $tag = 'disp-formula';
        }

        if ($token == CATCODE_MATH_SHIFT) {
            my $next_token = $parser->peek_next_token();

            if ($next_token == CATCODE_MATH_SHIFT) {
                # $LOG->warn("*** Found \$\$\n");

                $parser->consume_next_token();

                $double_dollar = 1;

                $token = BEGIN_DISPLAY_MATH;

                $tag = 'disp-formula';
            }
        }

        my $default = $parser->get_default_handler();

        my $formula;

        while (my $next_token = $parser->get_next_token()) {
            if (refaddr($next_token) == refaddr($end_token)) {
                if ($double_dollar) {
                    my $next_token = $parser->peek_next_token();

                    if ($next_token == CATCODE_MATH_SHIFT) {
                        $parser->consume_next_token();
                    } else {
                        $LOG->warn("*** Expected \$\$ but found \$\n");
                    }
                }

                last;
            }

            $formula .= $next_token;
        }

        if ($output->get_generate_mathml()) {
            my $mml = eval { tex2mml($formula) };

            if ($@) {
                $LOG->warn("$@\n");
            } elsif (nonempty($mml)) {
                $formula = $mml;

                undef $inner_tag;

                $content_type = "math/mathml";
            }
        }

        $parser->default_handler(qq{<$tag content-type="$content_type">\n});

        $parser->default_handler(qq{<$inner_tag>\n}) if defined $inner_tag;

        if (refaddr($token) == refaddr(BEGIN_DISPLAY_MATH)) {
            $parser->default_handler(qq{\\[\n});
        }

        $parser->default_handler($formula);

        if (refaddr($token) == refaddr(BEGIN_DISPLAY_MATH)) {
            $parser->default_handler(qq{\\]\n});
        }

        $parser->default_handler(qq{</$inner_tag>}) if defined $inner_tag;

        $parser->default_handler(qq{</$tag>});

        return;
    };
}

sub make_math_env_handler( $$ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        my $envname = $token->get_csname();

        my $start = qq{\\begin{$envname}};
        my $end   = qq{\\end{$envname}};

        if ($envname eq 'displaymath') {
            my $start = qq{\\[};
            my $end   = qq{\\]};
        }

        my $inner_tag = 'tex-math';
        my $content_type = 'math/tex';

        my $formula = $start;

        while (my $next_token = $parser->get_next_token()) {
            if (refaddr($next_token) == refaddr(END_TOKEN)) {
                my $end_envname = $parser->read_undelimited_parameter();

                $formula .= "\\end{$end_envname}";

                last if $end_envname eq $envname;
            } else {
                $formula .= $next_token;
            }
        }

        if ($output->get_generate_mathml()) {
            my $mml = eval { tex2mml($formula) };

            if ($@) {
                $LOG->warn("$@\n");
            } elsif (nonempty($mml)) {
                $formula = $mml;

                undef $inner_tag;

                $content_type = "math/mathml";
            }
        }

        $parser->default_handler(qq{<disp-formula content-type="$content_type">\n});

        $parser->default_handler(qq{<$inner_tag>\n}) if defined $inner_tag;

        $parser->default_handler($formula);

        $parser->default_handler(qq{</$inner_tag>\n}) if defined $inner_tag;

        $parser->default_handler(qq{</disp-formula>\n});

        return;
    };
}

sub make_par_handler( $ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        my $par = $parser->clear_output_buffer();

        return unless defined $par;

        $par =~ s{\s*\z}{}smx;

        return if empty $par;

        my $par_tag = $output->get_par_tag();

        if (nonempty($par_tag)) {
            $par = qq{<$par_tag>$par</$par_tag>};
        }

        $output->output("$par\n\n");

        return;
    };
}

sub default_handler( $ ) {
    my $parser = shift;
    my $token = shift;

    $token = q{&amp;} if $token eq '&';
    $token = q{&gt;}  if $token eq '>';
    $token = q{&lt;}  if $token eq '<';

    $parser->add_to_buffer("$token");

    return;
}

sub make_documentclass_handler( $ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        my $class = $parser->read_undelimited_parameter();

        $output->output(<<"EOF");
<?xml version="1.0" encoding="UTF-8"?>

<!DOCTYPE article
            PUBLIC "-//NLM//DTD JATS (Z39.96) Journal Publishing DTD with MathML3 v1.2 20190208//EN"
            "JATS-journalpublishing1-mathml3.dtd">

EOF

        return;
    };
}

sub make_document_handler( $ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        $output->output(<<"EOF");
<article xml:lang="en" xmlns:xlink="http://www.w3.org/1999/xlink">

<front>
    <journal-meta><journal-id/><issn/></journal-meta>
    <article-meta><title-group><article-title/></title-group></article-meta>
</front>

<body>

EOF

        return;
    };
}

sub make_enddocument_handler( $ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        $output->output(<<"EOF");

</body>

</article>
EOF

        return;
    };
}

sub make_begin_handler( $$ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        my $envname = $parser->read_undelimited_parameter();

        if (defined $envname) {
            if (defined(my $spec = $ENV_TO_TAG{$envname})) {
                my ($tag, $atts) = @{ $spec };

                $parser->default_handler("<$tag $atts>");
            } else {
                $parser->insert_tokens(make_csname_token($envname));
            }
        } else {
            croak("Missing argument for \\$token");
        }

        return;
    };
}

sub make_end_handler( $$ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        my $envname = $parser->read_undelimited_parameter();

        if (defined $envname) {
            if (defined(my $spec = $ENV_TO_TAG{$envname})) {
                my $tag = $spec->[0];

                $parser->default_handler("</$tag>");
            } else {
                $parser->insert_tokens(make_csname_token("end$envname"));
            }
        } else {
            croak("Missing argument for \\$token");
        }

        return;
    };
}

sub make_abstract_handler( $$ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        $parser->default_handler(qq{<front>\n});
        $parser->default_handler(qq{<article-meta>\n});
        $parser->default_handler(qq{<abstract>\n});
        $parser->default_handler("<p>");

        return;
    };
}

sub make_endabstract_handler( $$ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        $parser->default_handler("</p>");
        $parser->default_handler(qq{</abstract>\n});
        $parser->default_handler(qq{</article-meta>\n});
        $parser->default_handler(qq{</front>\n});

        return;
    };
}

sub make_quote_handler( $$ ) {
    my $output = shift;

    my $type = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        $parser->default_handler(qq{<disp-quote>\n});
        $parser->default_handler(qq{<p>\n});

        return;
    };
}

sub make_endquote_handler( $$ ) {
    my $output = shift;

    my $type = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        $parser->default_handler(qq{</p>\n});
        $parser->default_handler(qq{</disp-quote>\n});

        return;
    };
}

sub make_list_handler( $$ ) {
    my $output = shift;

    my $type = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        $parser->par();

        $output->set_list_ctr(0);

        $output->output(qq{<list list-type="$type">\n});

        $output->set_list_state(1);

        return;
    };
}

sub make_item_handler( $$ ) {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        $parser->par();

        if ($output->list_state() == 0) {
            $parser->warn("Found $token outside of a list\n");

            return;
        }

        if ($output->list_state() > 1) {
            $output->output(qq{\n</list-item>\n\n});
        }

        $output->set_list_state(2);

        $output->output(qq{<list-item>\n});

        $output->incr_list_ctr();

        return;
    };
}

sub make_end_list_handler( $$ ) {
    my $output = shift;

    my $type = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        $parser->par();

        if ($output->list_state() == 0) {
            $parser->warn("Found $token outside of a list\n");

            return;
        } elsif ($output->list_state() == 1) {
            $parser->warning("empty list");
        } else {
            $output->output("\n</list-item>\n")
        }

        ## GAH!!!!

        ## This, of course, invalid XML, but it's a solution to a
        ## corner I painted myself into.  If I'm going to implement
        ## TeX::Simple::HTML as a simple series of regexp
        ## replacements, I need a way to distinguish a </list> that
        ## closes an ordered list from a </list> that closes an
        ## unordered list.

        ## I'll stoop low enough to do this once.

        $output->output(qq{</list list-type="$type">\n});

        $output->set_list_state(0);

        return;
    };
}

######################################################################
##                                                                  ##
##                          BIBLIOGRAPHIES                          ##
##                                                                  ##
######################################################################

sub make_biblist_handler {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token  = shift;

        $parser->par();

        my $envname = $token->get_csname();

        $output->output(qq{\n<ref-list>\n});

        $output->output(qq{<title>References</title>\n});

        return;
    };
}

sub make_endbiblist_handler {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token  = shift;

        my $envname = $token->get_csname();

        $parser->par();

        if ($output->is_in_bibitem()) {
            $output->output(qq{</mixed-citation>\n</ref>\n});

            $output->set_par_tag('p');
        }

        $output->output(qq{\n</ref-list>\n});

        return;
    };
}

sub make_bibitem_handler {
    my $output = shift;

    return sub {
        my $parser = shift;
        my $token = shift;

        $parser->par();

        if ($output->is_in_bibitem()) {
            $output->output(qq{</mixed-citation>\n</ref>\n});

            $output->set_par_tag('p');
        }

        my $label = $parser->scan_optional_argument();

        my $cite_key = $parser->read_undelimited_parameter();

        $parser->skip_optional_spaces();

        $output->output("\n<ref>\n");
        $output->output("<mixed-citation>\n");

        $output->set_in_bibitem(1);

        $output->set_par_tag('');

        return;
    };
}

my %COMPOUND_FIELD = array_to_hash qw(book conference contribution
    partial reprint translation);

sub __parse_key_pairs($$$);

sub __parse_key_pairs($$$) {
    my $bibitem = shift;

    my $entries = shift;

    my $amsrefs = shift;

    ## Assume normal catcodes

    while ($entries =~ s/^ ,? \s* ($TeX::Patterns::LETTER+) \s* = \s* \{ ($BALANCED_TEXT) \}//smx) {
        my $key = lc $1;

        my $value = trim($2);

        my %atts;

        if ($entries =~ s/\A \s* \* \s* \{ ($BALANCED_TEXT) \} //smx) {
            my $attributes = trim($1);

            while ($attributes =~ s/^ ,? \s* ($TeX::Patterns::LETTER+) \s* = \s* \{ ($BALANCED_TEXT) \}//smx) {
                my $att_key = $1;

                my $att_value = trim($2);

                $atts{$att_key} = $att_value;

                $attributes =~ s/^[\s,]+//;
            }

            if (nonempty($attributes)) {
                $LOG->warn("Unparseable entries for attributes: [$attributes]\n");
            }
        }

        if ($COMPOUND_FIELD{$key} && $value =~ /\A \s* (\w+) \s* =/smx) {
            my $citekey = $bibitem->get_citekey(); # ???
            my $bibtype = $bibitem->get_type();

            my $subitem = TeX::AMSrefs::BibItem->new({ type    => $bibtype,
                                                       citekey => $citekey,
                                                       inner   => 1 });

            $subitem->set_container($amsrefs);

            __parse_key_pairs($subitem, $value, $amsrefs);

            $bibitem->add_entry($key, $subitem, \%atts);
        } else {
            $bibitem->add_entry($key, $value, \%atts);
        }

        $entries =~ s/^[\s,]+//;
    }

    if (nonempty($entries)) {
        $LOG->warn("Unparseable entries for bibitem: [$entries]\n");
    }

    return $bibitem;
}

sub make_bib_handler {
    my $output = shift;

    my $amsrefs_tex  = $output->get_amsrefs_tex();
    my $amsrefs_jpts = $output->get_amsrefs_jpts();

    return sub {
        my $parser = shift;
        my $token  = shift;

        $parser->par();

        if ($output->is_in_bibitem()) {
            $output->output(qq{</mixed-citation>\n</ref>\n});

            $output->set_par_tag('p');
        }

        $output->set_in_bibitem(0);

        my $starred = $parser->is_starred();

        my $cite_key = $parser->read_undelimited_parameter();
        my $bib_type = $parser->read_undelimited_parameter();

        my $entries = $parser->read_undelimited_parameter();

        my $bibitem = TeX::AMSrefs::BibItem->new({ type    => $bib_type,
                                                   citekey => $cite_key });

        $bibitem->set_container($amsrefs_tex);

        __parse_key_pairs($bibitem, $entries, $amsrefs_tex);

        $bibitem->resolve_xrefs();

        if ($starred) {
            $amsrefs_tex->remember_bibitem($bibitem);
            $amsrefs_jpts->remember_bibitem($bibitem);

            return;
        }

        my $mixed   = $amsrefs_tex->format_bib_item($bibitem);
        my $element = $amsrefs_jpts->format_bib_item($bibitem);

        return unless nonempty($mixed) || nonempty($element);

        my $dual = nonempty($mixed) && nonempty($element);

        $output->output(qq{<ref>\n});

        $output->output(qq{<citation-alternatives>\n}) if $dual;

        if (nonempty($element)) {
            $output->output(qq{<element-citation>\n});
            $output->output($element);
            $output->output(qq{\n</element-citation>\n});
        }

        if (nonempty($mixed)) {
            $output->output(qq{<mixed-citation>\n});

            my $mixed_citation = $parser->expand_string($mixed);

            $output->output(qq{\n</mixed-citation>\n});
        }

        $output->output(qq{</citation-alternatives>\n}) if $dual;

        $output->output(qq{</ref>\n});
    };
}

sub do_issuetext {
    my $parser = shift;
    my $token  = shift;

    my $arg = $parser->read_undelimited_parameter();

    $parser->insert_tokens($parser->tokenize(qq{no.~$arg}));

    return;
}

######################################################################
##                                                                  ##
##                               XML                                ##
##                                                                  ##
######################################################################

## \openXMLelement{TAG}{ATTRIBUTES}

sub do_openXMLelement {
    my $parser = shift;
    my $token  = shift;

    my $tag  = $parser->read_undelimited_parameter();
    my $atts = $parser->read_undelimited_parameter();

    $parser->default_handler("<$tag");

    if (nonempty($atts)) {
        $parser->default_handler(" $atts");
    }

    $parser->default_handler(">");

    return;
}

sub do_closeXMLelement {
    my $parser = shift;
    my $token  = shift;

    my $tag  = $parser->read_undelimited_parameter();

    $parser->default_handler("</$tag>");

    return;
}

1;

__END__
