package TeX::AMSrefs::JPTS;

use strict;
use warnings;

use version; our $VERSION = qv '1.3.0';

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
##                         PACKAGE IMPORTS                          ##
##                                                                  ##
######################################################################

use Class::Std;

use TeX::AMSrefs::BibItem;

use TeX::Utils::Misc;

######################################################################
##                                                                  ##
##                            ATTRIBUTES                            ##
##                                                                  ##
######################################################################

my %xref_list :ATTR;

######################################################################
##                                                                  ##
##                         CLASS VARIABLES                          ##
##                                                                  ##
######################################################################

my %BIB_SPEC;

######################################################################
##                                                                  ##
##                            CONSTANTS                             ##
##                                                                  ##
######################################################################

use constant ETAL_TEXT => 'et al.';

######################################################################
##                                                                  ##
##                           GLOBAL DATA                            ##
##                                                                  ##
######################################################################

######################################################################
##                                                                  ##
##                           CONSTRUCTOR                            ##
##                                                                  ##
######################################################################

sub START {
    my ($self, $id, $args_ref) = @_;

    for my $citekey ('alii', 'etal', 'et al.') {
        my $abbrev = TeX::AMSrefs::BibItem->new({ type    => 'name',
                                                  citekey => $citekey,
                                                  starred => 1 });

        $abbrev->add_entry(name => ETAL_TEXT);

        $self->remember_bibitem($abbrev);
    }

    return;
}

######################################################################
##                                                                  ##
##                      MISCELLANEOUS METHODS                       ##
##                                                                  ##
######################################################################

sub remember_bibitem {
    my $self = shift;

    my $bibitem = shift;

    my $citekey = $bibitem->get_citekey();

    return $xref_list{ident $self}->{$citekey} = $bibitem;
}

sub retrieve_xref {
    my $self = shift;

    my $citekey = shift;

    return $xref_list{ident $self}->{$citekey};
}

######################################################################
##                                                                  ##
##                        UTILITY FUNCTIONS                         ##
##                                                                  ##
######################################################################

sub get_field {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $field = $bibitem->get_field($key);

    ## Unpack compound values.

    if (eval { $field->isa("TeX::AMSrefs::BibItem::Entry") }) {
        my $value = $field->get_value();

        if (eval { $value->isa("TeX::AMSrefs::BibItem") }) {
            return $value;
        }
    }

    my $is_array = ref($field) eq 'ARRAY';

    my @entries = $is_array ? @{ $field } : ($field);

    for my $entry (@entries) {
        next unless defined $entry;

        next if $entry->get_attribute("__processed");

        my $value = $entry->get_value();

        $value =~ s{\s*<BR>\s*}{ }ismg;

        $entry->set_value($value);
        $entry->set_attribute("__processed", 1);
    }

    if ($is_array) {
        return wantarray ? @{ $field } : $field;
    } else {
        return $field;
    }
}


sub format_name( $ ) {
    my $self = shift;

    my $raw_name = shift;

    my ($surname, $given, $jr) = split /,\s*/, $raw_name;

    my $name = qq{<name>\n};

    if (nonempty($surname)) {
        $name .= qq{    <surname>$surname</surname>\n};
    }

    if (nonempty($given)) {
        $name .= qq{    <given-names>$given</given-names>\n};
    }

    if (nonempty($jr)) {
        $name .= qq{    <suffix>$jr</suffix>\n};
    }

    $name .= qq{\n</name>\n};

    return $name;
}

sub print_series($$$$$@) {
    my $self = shift;

    my $pre   = shift;
    my $sep_1 = shift;
    my $sep_2 = shift;
    my $sep_3 = shift;
    my $post  = shift;

    my @items = @_;

    return join "\n", @items;
}

sub print_standard_series(@) {
    my $self = shift;

    return $self->print_series('', q{ and }, q{, }, q{, and }, '', @_);
}

sub print_names {
    my $self = shift;

    my $pre  = shift;
    my $post = shift;

    my @names = @_;

    return join("\n", @names);
}

sub print_title {
    my $self = shift;

    my $bibitem = shift;

    my $title = $self->get_field($bibitem, 'title');

    if (nonempty(my $part = $self->get_field($bibitem, 'part'))) {
        $title .= qq{. $part};
    }

    if (nonempty(my $subtitle = $self->get_field($bibitem, 'subtitle'))) {
        $title .= qq{: $subtitle};
    }

    return qq{<article-title>$title</article-title>};
}

sub print_source {
    my $self = shift;

    my $bibitem = shift;

    my $title = $self->get_field($bibitem, 'title');

    if (nonempty(my $part = $self->get_field($bibitem, 'part'))) {
        $title .= qq{. $part};
    }

    if (nonempty(my $subtitle = $self->get_field($bibitem, 'subtitle'))) {
        $title .= qq{: $subtitle};
    }

    return qq{<source>$title</source>};
}

sub apply_style {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $tag = shift;
    my $atts = shift;

    my $text = $self->get_field($bibitem, $key);

    if (nonempty($tag)) {
        if (nonempty($atts)) {
            $text = qq{<$tag $atts>$text</$tag>};
        } else {
            $text = qq{<$tag>$text</$tag>};
        }
    }

    return $text;
}

######################################################################
##                                                                  ##
##                            FORMATTING                            ##
##                                                                  ##
######################################################################
## TODO: This is only part of what amsrefs does.

sub adjust_bibfields( $ ) {
    my $self = shift;

    my $bibitem = shift;

    my $type = $bibitem->get_type();

    # if ($type eq 'article') {
    #     if (! $bibitem->has_volume()) {
    #         if ($bibitem->has_number()) {
    #             $bibitem->add_entry(volume => $bibitem->get_number());
    #             $bibitem->delete_entry('number');
    #         }
    #     }
    # }

    return;
}

sub format_bib_item {
    my $self = shift;

    my $bibitem = shift;
    my $anchor  = shift;
    my $label   = shift;

    $self->adjust_bibfields($bibitem);

    my $html;

    # if (nonempty($label)) {
    #     my $label = qq{<strong>[$label]</strong>};
    # 
    #     if (nonempty($anchor)) {
    #         $label = qq{<a name="$anchor">$label</a>};
    #     }
    # 
    #     $html = qq{<dt>$label</dt>\n<dd>\n};
    # }

    my $type = $bibitem->get_type();

    if ($type eq 'article') {
        if (   $bibitem->has_booktitle()
            || $bibitem->has_book()
            || $bibitem->has_conference()) {
            $type = 'incollection';
        }
    }

    my $spec = $BIB_SPEC{$type};

    for my $format (@{ $spec }) {
        my ($key, $punct, $prefix, $formatter) = @{ $format };

        my $field = $self->get_field($bibitem, $key);

        next unless $key eq 'transition' || $field;

        my $formatted_field = $field;

        if (ref($formatter) eq 'ARRAY') {
            my ($method, @args) = @{ $formatter };

            $formatted_field = $self->$method($bibitem, $key, @args);
        } elsif (ref($formatter) eq 'CODE') {
            $formatted_field = $self->$formatter($bibitem, $key);
        } elsif (nonempty $formatter) {
            $formatted_field = $self->$formatter($bibitem, $key);
        }

        if (defined $formatted_field) {
            $html .= $prefix;
            $html .= $formatted_field;
        }
    }

    # if (nonempty($label)) {
    #     $html .= "</dd>";
    # }

    return $html;
}

sub print_primary {
    my $self = shift;

    my $bibitem = shift;

    if ($bibitem->has_author()) {
        return $self->print_authors($bibitem, 'author');
    } elsif ($bibitem->has_editor()) {
        return $self->print_editors($bibitem, 'editor');
    } elsif ($bibitem->has_translator()) {
        return $self->print_translators($bibitem, 'translator');
    }
}

sub print_authors {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my @authors = $self->get_field($bibitem, $key);

    my @names;

    push @names, map { $self->format_name($_) } @authors;

    return $self->print_names(q{}, q{}, @names);
}

sub print_editors {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my @editors = $self->get_field($bibitem, $key);

    my $pl = @editors == 1 ? "" : "s";

    my @names;

    push @names, map { $self->format_name($_) } @editors;

    my @persons = map { qq{<person-group person-group-type="editor">\n$_\n</person-group>} } @names;

    return join "\n", @persons;
}

sub print_translators {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my @translators = $self->get_field($bibitem, $key);

    my @names;

    push @names, map { $self->format_name($_) } @translators;

    my @persons = map { qq{<person-group person-group-type="translator">\n$_\n</person-group>} } @names;

    return join "\n", @persons;
}

sub print_name_list {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $field = $self->get_field($bibitem, $key);

    my @names = map { $self->format_name($_) } $self->get_field($bibitem, $key);

    return $self->print_names(q{}, qq{}, @names);
}

sub print_date {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift || 'date';

    my $raw_date = $self->get_field($bibitem, $key)->get_value();

    my $date_string;

    if ( $raw_date =~ /\A \d+(-\d+){0,2} \z/smx ) {
        my ($year, $month, $day) = split /-+/, $raw_date;

        my @pieces;

        if (nonempty($year)) {
            push @pieces, qq{<year>$year</year>};
        }

        if (nonempty($month)) {
            push @pieces, qq{<month>$month</month>};
        }

        if (nonempty($day)) {
            push @pieces, qq{<day>$day</day>};
        }

        return join "\n", @pieces;
    }

    return;
}

sub print_doi {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $doi = $self->get_field($bibitem, $key);

    $doi = xml_encode($doi);

    return qq{<named-content content-type="DOI">$doi</named-content>}
}

sub print_arXiv {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $arXiv = $self->get_field($bibitem, $key);

    my $arxiv_number;

    if ($arXiv =~ m{\A \[.*?\]/ (.*) \z} || $arXiv =~ m{\A ([^\[\]]+)?}) {
        $arxiv_number = $1;
    }

    if (nonempty($arxiv_number)) {
        my $url = qq{https://arxiv.org/abs/$arxiv_number};

        return ext_link($url, $arXiv);
    }

    return;
}

sub ext_link( $;$ ) {
    my $url = shift;
    my $display_text = shift;

    $display_text = $url if empty $display_text;

    $url = xml_encode($url);
    $display_text = xml_encode($url);

    return qq{<ext-link xlink:href="$url">$display_text</ext-link>};
}

sub print_wikiurl {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $wiki_url = $self->get_field($bibitem, $key);

    my $url = qq{https://en.wikipedia.org/wiki/$wiki_url};

    return ext_link($url);
}

sub print_edition {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $field = $self->get_field($bibitem, $key)->get_value();

    return qq{<edition>$field</edition>\n};
}

sub print_type {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $type = $self->get_field($bibitem, $key)->get_value();

    return qq{<named-content content-type="type">$type</named-content>};
}

sub print_thesis_type {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $type = $self->get_field($bibitem, $key)->get_value();

    if ($type =~ /^p/) {
        $type = "Ph.D. Thesis";
    } elsif ($type =~ /^m/) {
        $type = "Master's Thesis";
    }

    return qq{<named-content content-type="thesis type">$type</named-content>};
}

sub format_pages( $ ) {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $pages = $self->get_field($bibitem, $key);

    if ($pages =~ m{(\d+)(?:[-\x{2013}]+(\d+))?}) {
        my $fpage = $1;
        my $lpage = $2;

        my $text = qq{<fpage>$fpage</fpage>\n};

        if (nonempty($lpage)) {
            $text .= qq{<lpage>$lpage</lpage>\n};
        }

        return $text;
    }

    return;
}

sub url( $ ) {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my $url = $self->get_field($bibitem, $key);

    return ext_link($url);
}

######################################################################
##                                                                  ##
##                         COMPOUND FIELDS                          ##
##                                                                  ##
######################################################################

sub format_inner {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;
    my $type    = shift;

    my $inner = $bibitem->get_inner_item($key)->clone();

    $inner->set_type($type);
    $inner->set_inner(1);

    return $self->format_bib_item($inner);
}

sub print_book {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    return $self->format_inner($bibitem, $key, 'innerbook');
}

sub print_conference {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    return $self->format_inner($bibitem, $key, 'conference');
}

sub print_conference_details {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my @fields;

    if (nonempty(my $address = $self->get_field($bibitem, 'address'))) {
        push @fields, qq{<publisher-loc>$address</publisher-loc>};
    }

    if (nonempty(my $date = $self->get_field($bibitem, 'date'))) {
        push @fields, qq{<year>$date</year>};
    }

    return join "\n", @fields;
}

sub format_one_contribution {
    my $self = shift;
    my $contribution = shift;

    if (eval { $contribution->isa('TeX::AMSrefs::BibItem') }) {
        $contribution->set_type('contribution');

        return $self->format_bib_item($contribution);
    } else {
        return $contribution;
    }
}

sub print_contributions {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my @contributions = $self->get_field($bibitem, $key);

    my @items = map { $_->get_value() } @contributions;

    my @formatted = map { $self->format_one_contribution($_) } @items;

    return $self->print_standard_series(@formatted);
}

sub print_partials {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my @partials = $self->get_field($bibitem, $key);

    my @items;

    for my $partial (@partials) {
        my $value = $partial->get_value();

        if (eval { $value->isa("TeX::AMSrefs::BibItem") }) {
            push @items, $value;
        } else {
            my $xref = $self->retrieve_xref($value);

            if (defined $xref) {
                my $clone = $xref->clone();
                $clone->set_inner(1);

                push @items, $clone;
            } else {
                $LOG->error("Xref '$value' undefined\n");
            }
        }
    }

    return unless @items;

    my @formatted = map { $self->format_bib_item($_) } @items;

    return $self->print_standard_series(@formatted);
}

sub print_reprint {
    my $self = shift;

return;

    my $bibitem = shift;
    my $key     = shift;

    my $reprint = $bibitem->get_inner_item($key)->clone();

    $reprint->set_type('book');
    $reprint->set_inner(1);

    my $copula = $reprint->get_copula() || "reprinted in";

    return concat $copula, " ", $self->format_bib_item($reprint);
}

sub print_reviews {
    my $self = shift;

    my $bibitem = shift;
    my $key     = shift;

    my @reviews = map { qq{<named-content content-type="MathSciNet review number">$_</named-content>} } $self->get_field($bibitem, $key);

    return join "\n", @reviews;
}

sub print_translation {
    my $self = shift;

return;

    my $bibitem = shift;
    my $key     = shift;

    my $translation = $bibitem->get_inner_item($key);

    if (defined $translation) {
        my $language = $translation->get_language() || 'English';

        my $html = "$language transl.";

        if (my $pages = $translation->get_pages()) {
            $html .= ", ";
        } else {
            $html .= " in ";
        }

        my $item = $translation->clone();

        $item->delete_entry('language');
        $item->set_inner(1);

        $html .= $self->format_bib_item($item);

        return $html;
    }

    return;
}

######################################################################
##                                                                  ##
##                      FORMAT SPECIFICATIONS                       ##
##                                                                  ##
######################################################################

sub define_bibspec( $$ ) {
    my $self = shift;

    my $bib_type = shift;
    my $bib_spec = shift;

    $BIB_SPEC{$bib_type} = $bib_spec;

    return;
}

$BIB_SPEC{article} = [
    [ author           => q{},  q{},           \&print_authors ],
    [ title            => q{,}, q{ },          \&print_title ],
    [ contribution     => q{,}, q{ },          \&print_contributions ],
    [ partial          => q{.}, q{ },          \&print_partials ],
    [ journal          => q{,}, q{ },          [ apply_style => 'source' ] ],
    [ volume           => q{},  q{ },          [ apply_style => 'volume' ] ],
    [ date             => q{},  q{ },          \&print_date ],
    [ number           => q{,}, q{ },          [ apply_style => 'issue' ] ],
    [ pages            => q{,}, q{ },          q{format_pages} ],
#    [ status           => q{,}, q{ },          q{} ],
    [ eprint           => q{,}, q{ },          \&url ],
    [ translation      => q{;}, q{ },          \&print_translation ],
    [ reprint          => q{;}, q{ },          \&print_reprint ],
    [ review           => q{},  q{ },          q{print_reviews} ],
    [ doi              => q{,}, q{ },          q{print_doi} ],
];

$BIB_SPEC{book} = [
    [ transition       => q{}  , q{}  ,        \&print_primary ],
    [ title            => q{,} , q{ } ,        [ apply_style => 'source' ] ],
    [ edition          => q{,} , q{ } ,        \&print_edition ],
    [ editor           => q{}  , q{ } ,        \&print_editors ],
    [ translator       => q{,} , q{ } ,        \&print_translators ],
    [ contribution     => q{,} , q{ } ,        \&print_contributions ],
    [ series           => q{,} , q{ } ,        [ apply_style => 'series' ] ],
    [ volume           => q{,} , q{ } ,        [ apply_style => 'volume' ] ],
    [ publisher        => q{,} , q{ } ,        [ apply_style => 'publisher-name' ] ],
    [ organization    => q{,}  , q{ }   ,      [ apply_style => 'publisher-name' ] ],
    [ address          => q{,} , q{ } ,        [ apply_style => 'publisher-loc' ] ],
    [ date             => q{,} , q{ } ,        \&print_date ],
#    [ status           => q{,} , q{ } ,        q{} ],
    [ translation      => q{}  , q{ } ,        \&print_translation ],
    [ reprint          => q{;} , q{ } ,        \&print_reprint ],
    [ eprint           => q{.},  q{ },         \&url ],
    [ review           => q{}  , q{ } ,        q{print_reviews} ],
];

$BIB_SPEC{partial} = [
    [ part            => q{}  ,  q{}  ,        q{} ],
    [ subtitle        => q{:} ,  q{ } ,        [ apply_style => 'article-title' ] ],
    [ contribution    => q{,} ,  q{ } ,        \&print_contributions ],
    [ journal          => q{,}, q{ },          [ apply_style => 'source' ] ],
    [ volume          => q{}  ,  q{ } ,        [ apply_style => 'volume' ] ],
    [ date            => q{}  ,  q{ } ,        \&print_date ],
    [ number          => q{,} ,  q{ } ,        [ apply_style => 'issue' ] ],
    [ pages           => q{,} ,  q{ } ,        q{format_pages} ],
];

$BIB_SPEC{contribution} = [
    [ type            => q{} ,  q{}     ,      \&print_type ],
    [ author          => q{} ,  q{ by } ,      \&print_name_list ],
];

$BIB_SPEC{"collection.article"} = [
    [ transition      => q{}   , q{}    ,      \&print_primary ],
    [ title           => q{,}  ,  q{ }  ,      \&print_title ],
    [ contribution    => q{,}  ,  q{ }  ,      \&print_contributions ],
    [ conference      => q{,}  ,  q{ }  ,      \&print_conference ],
    [ book            => q{,}  ,  q{ }  ,      \&print_book ],
    [ booktitle       => q{,}  ,  q{ }  ,      [ apply_style => 'source' ] ],
    [ date            => q{,}  ,  q{ }  ,      \&print_date ],
    [ pages           => q{,}  ,  q{ }  ,      q{format_pages} ],
#    [ status          => q{,}  ,  q{ }  ,      q{} ],
    [ eprint          => q{,}  ,  q{ },        \&url ],
    [ translation     => q{}   ,  q{ }  ,      \&print_translation ],
    [ reprint         => q{;}  ,  q{ }  ,      \&print_reprint ],
    [ review          => q{}   ,  q{ }  ,      q{print_reviews} ],
    [ doi             => q{,}  ,  q{ }  ,      q{print_doi} ],
];

$BIB_SPEC{conference} = [
    [ title           => q{}   ,  q{}   ,      \&print_source ],
    [ transition      => q{}   ,  q{}   ,      \&print_conference_details ],
];

$BIB_SPEC{innerbook} = [
    [ title           => q{,}  ,  q{ }  ,      \&print_source ],
    [ edition         => q{,}  ,  q{ }  ,      \&print_edition ],
    [ editor          => q{ }  ,  q{ }  ,      \&print_editors ],
    [ translator      => q{,}  ,  q{ }  ,      \&print_translators ],
    [ contribution    => q{,}  ,  q{ }  ,      \&print_contributions ],
    [ series           => q{,} , q{ } ,        [ apply_style => 'series' ] ],
    [ volume          => q{,}  ,  q{ }  ,      [ apply_style => 'volume' ] ],
    [ publisher       => q{,}  ,  q{ }  ,      [ apply_style => 'publisher-name' ] ],
    [ organization    => q{,}  , q{ }   ,      [ apply_style => 'publisher-name' ] ],
    [ address         => q{,}  ,  q{ }  ,      [ apply_style => 'publisher-loc' ] ],
    [ date            => q{,}  ,  q{ }  ,      \&print_date ],
];

$BIB_SPEC{report} = [
    [ transition      => q{}   , q{}    ,      \&print_primary ],
    [ title           => q{,}  , q{ }   ,      \&print_source ],
    [ edition         => q{,}  , q{ }   ,      \&print_edition ],
    [ contribution    => q{,}  , q{ }   ,      \&print_contributions ],
    [ number           => q{,}, q{ },          [ apply_style => 'volume' ] ],
    [ series           => q{,} , q{ } ,        [ apply_style => 'series' ] ],
    [ organization    => q{,}  , q{ }   ,      [ apply_style => 'publisher-name' ] ],
    [ address         => q{,}  , q{ }   ,      [ apply_style => 'publisher-loc' ] ],
    [ date            => q{,}  , q{ }   ,      \&print_date ],
    [ eprint          => q{,}  , q{ }   ,      \&url ],
#    [ status          => q{,}  , q{ }   ,      q{} ],
    [ translation     => q{}   , q{ }   ,      \&print_translation ],
    [ reprint         => q{;}  , q{ }   ,      \&print_reprint ],
    [ review          => q{}   , q{ }   ,      q{print_reviews} ],
];

$BIB_SPEC{thesis} = [
    [ author          => q{}   ,  q{}   ,      \&print_authors ],
    [ title           => q{,}  ,  q{ }  ,      \&print_source ],
    [ type            => q{,}  ,  q{ }  ,      \&print_thesis_type ],
    [ organization    => q{,}  ,  q{ }  ,      [ apply_style => 'publisher-name' ] ],
    [ address         => q{,}  ,  q{ }  ,      [ apply_style => 'publisher-loc' ] ],
    [ date            => q{,}  ,  q{ }  ,      \&print_date ],
    [ eprint          => q{,}  ,  q{ }  ,      \&url ],
#    [ status          => q{,}  ,  q{ }  ,      q{} ],
    [ translation     => q{}   ,  q{ }  ,      \&print_translation ],
    [ reprint         => q{;}  ,  q{ }  ,      \&print_reprint ],
    [ review          => q{}   ,  q{ }  ,      q{print_reviews} ],
];

$BIB_SPEC{eprint} = [
    [ author => q{},  q{},  \&print_authors ],
    [ title  => q{,}, q{ }, \&print_source  ],
    [ arxiv  => q{,}, q{ }, \&print_arXiv   ],
    [ date   => q{,}, q{ }, \&print_date    ],
];

$BIB_SPEC{wiki} = [
    [ wiki     => q{} , q{} , \&print_source ],
    [ title    => q{,}, q{ }, \&print_title ],
    [ date     => q{,}, q{ }, \&print_date ],
    [ wikiurl  => q{,}, q{ }, \&print_wikiurl ],
];

$BIB_SPEC{name} = [
    [ name            => q{}   ,  q{}   ,      \&print_authors ],
];

$BIB_SPEC{publisher} = [
    [ publisher => q{,}, q{ }, [ apply_style => 'publisher-name' ] ],
    [ address   => q{,}, q{ }, [ apply_style => 'publisher-loc' ] ],
];

$BIB_SPEC{periodical}            = $BIB_SPEC{book};
$BIB_SPEC{collection}            = $BIB_SPEC{book};
$BIB_SPEC{proceedings}           = $BIB_SPEC{book};
$BIB_SPEC{manual}                = $BIB_SPEC{book};
$BIB_SPEC{miscellaneous}         = $BIB_SPEC{book};
$BIB_SPEC{misc}                  = $BIB_SPEC{miscellaneous};
$BIB_SPEC{unpublished}           = $BIB_SPEC{book};
$BIB_SPEC{incollection}          = $BIB_SPEC{"collection.article"};
$BIB_SPEC{inproceedings}         = $BIB_SPEC{"collection.article"};
$BIB_SPEC{"proceedings.article"} = $BIB_SPEC{"collection.article"};
$BIB_SPEC{techreport}            = $BIB_SPEC{report};

1;

__END__

abbrev
alternatives
annotation
article-title
bold
chapter-title
chem-struct
collab
collab-alternatives
comment
conf-acronym
conf-date
conf-loc
conf-name
conf-sponsor
data-title
date
date-in-citation
day
edition
elocation-id
email
etal
ext-link
fixed-case
fpage
gov
index-term
index-term-range-end
inline-formula
inline-graphic
inline-media
institution
institution-wrap
isbn
issn
issn-l
issue
issue-id
issue-part
issue-title
italic
label
lpage
milestone-end
milestone-start
monospace
month
name
name-alternatives
named-content
object-id
overline
page-range
part-title
patent
person-group
private-char
pub-id
publisher-loc
publisher-name
role
roman
ruby
sans-serif
sc
season
series
size
source
std
strike
string-date
string-name
styled-content
sub
sup
supplement
trans-source
trans-title
underline
uri
version
volume
volume-id
volume-series
year

