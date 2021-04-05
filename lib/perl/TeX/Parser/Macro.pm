package TeX::Parser::Macro;

use strict;
use warnings;

use version; our $VERSION = qv '1.0.0';

use TeX::Class;

use TeX::TokenList;

use Carp;

use base qw(Exporter);

our %EXPORT_TAGS = ( factories => [ qw(make_macro) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{factories} } );

our @EXPORT = ();

my %param_text_of :ATTR(:name<param_text>   :type<TeX::TokenList>);
my %macro_text_of :ATTR(:name<macro_text> :type<TeX::TokenList>);

sub make_macro( $$ ) {
    my $param_text   = shift;
    my $macro_text = shift;

    return __PACKAGE__->new({ param_text => $param_text,
                              macro_text => $macro_text });
}

sub expand {
    my $self = shift;

    my $parser = shift;
    my $cur_tok = shift;

    my $param_text = $self->get_param_text();
    my $macro_text = $self->get_macro_text();

    my @params = $parser->read_macro_parameters(@{ $param_text });

    my @expansion;

    for my $token (@{ $macro_text }) {
        if ($token->is_param_ref()) {
            my $param_no = $token->get_param_no();

            if (! defined $params[$param_no]) {
                croak "Undefined parameter $param_no while expanding $cur_tok";
            } else {
                push @expansion, @{ $params[$param_no] };
            }
        } else {
            push @expansion, $token;
        }
    }

    $parser->insert_tokens(@expansion);

    return;
}

1;

__END__
