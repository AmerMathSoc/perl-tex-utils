package TeX::Logger;

use strict;
use warnings;

use version; our $VERSION = qv '1.0.0';

use base qw(Exporter);

our %EXPORT_TAGS = ();

our @EXPORT_OK = ();

our @EXPORT;

use Exception::Class qw(TeX::Logger::Error);

use TeX::Logger::Sink qw(:constants);

######################################################################
##                                                                  ##
##                            ATTRIBUTES                            ##
##                                                                  ##
######################################################################

use Class::Std;

my %sinks_of :ATTR;

my %default_handle_of :ATTR( :name<default_handle> :default<*STDERR> );
my %default_level_of  :ATTR( :name<default_level>  :default<LOG_NORMAL> );
my %default_mode_of   :ATTR( :name<default_mode>   :default<0664> );
my %die_on_fatal_of   :ATTR( :name<die_on_fatal>   :default<0> );

######################################################################
##                                                                  ##
##                             FACTORY                              ##
##                                                                  ##
######################################################################

## In normal circumstances, TeX::Logger should act as a singleton
## class.  This can be accomplished by having all modules that need to
## use it call TeX::Logger->get_logger().  Explicit calls to
## TeX::Logger->new() are not interdicted, but should rarely be
## appropriate.

GET_LOGGER: {
    my $LOGGER;

    sub get_logger {
        my $class = shift;
        my $arg_ref = shift || {};

        return $LOGGER if defined $LOGGER;

        return $LOGGER = __PACKAGE__->new($arg_ref);
    }

    ## Avoid finalization segfault.
    END { undef $LOGGER; }
}

######################################################################
##                                                                  ##
##                           SUBROUTINES                            ##
##                                                                  ##
######################################################################

sub START {
    my ($self, $ident, $arg_ref) = @_;

    # initialize empty hashref of sinks
    $sinks_of{$ident} = {};

    $self->add_sink('notice', { handle => $self->get_default_handle(),
                                level  => LOG_NORMAL });

    return;
}

######################################################################
##                                                                  ##
##                           PLUMBING                               ##
##                      (SINK MAINTENANCE)                          ##
##                                                                  ##
######################################################################

## manage pool of Sinks
#
# Note that Sink name is the first parameter; other parameters
# are passed as a hash.

sub add_sink($$;$) {
    my $self = shift;

    my $name     = shift;
    my $paramref = shift || {};

    my $sinks = $sinks_of{ident $self};

    if (exists $sinks->{$name}) {
        TeX::Logger::Error->throw("Sink $name already exists");
    }

    # This might throw an exception, but if it does we will
    # just pass it up the line to whoever called here.

    $sinks->{$name} = 
        new TeX::Logger::Sink({ handle => $self->get_default_handle(),
                                level  => $self->get_default_level(),
                                mode   => $self->get_default_mode(),
                                append => 0,
                                %{ $paramref }
                              });

    return;
}

sub delete_sink($$;$) {
    my $self = shift;

    my $name = shift;
    my $error_if_undef = shift;
    
    my $sinks = $sinks_of{ident $self};
    
    if ( exists( $sinks->{$name} )) {
        delete $sinks->{$name};
    } elsif ($error_if_undef) {
        TeX::Logger::Error->throw("Can't delete sink '$name': it doesn't exist");
    }

    return;
}

sub get_sink($$;$) {
    my $self = shift;

    my $name = shift;
    my $error_if_undef = shift;
    
    my $sinks = $sinks_of{ident $self};
    
    if ( exists( $sinks->{$name} )) {
        return $sinks->{$name};
    } elsif ( $error_if_undef ) {
        TeX::Logger::Error->throw("Sink '$name' doesn't exist");
    }
    
    return;
}

sub set_sink_level {
    my $self = shift;

    my $name           = shift;
    my $level          = shift;
    my $error_if_undef = shift;
    
    my $sinks = $sinks_of{ident $self};
    
    if ( ! defined($sinks->{$name}) && $error_if_undef ) {
        TeX::Logger::Error->throw("Unknown sink '$name'");
    }
    
    return $sinks->{$name}->set_level($level);
}

sub set_sink_mode {
    my $self = shift;

    my $name           = shift;
    my $mode           = shift;
    my $error_if_undef = shift;
    
    my $sinks = $sinks_of{ident $self};
    
    if ( ! defined($sinks->{$name}) && $error_if_undef ) {
        TeX::Logger::Throw->throw("Uknown sink '$name'");
    }
    
    return $sinks->{$name}->set_mode($mode);
}

sub push_sink_level($$$;$) {
    my $self = shift;

    my $name           = shift;
    my $level          = shift;
    my $error_if_undef = shift;
    
    my $sinks = $sinks_of{ident $self};
    
    if ( ! defined($sinks->{$name}) && $error_if_undef ) {
        TeX::Logger::Error->throw("Uknown sink '$name'");
    }
    
    return $sinks->{$name}->push_level($level);
}

sub pop_sink_level($$;$) {
    my $self = shift;

    my $name           = shift;
    my $error_if_undef = shift;
    
    my $sinks = $sinks_of{ident $self};
    
    if ( ! defined($sinks->{$name}) && $error_if_undef ) {
        TeX::Logger::Error->throw("Unknown sink '$name'");
    }
    
    return $sinks->{$name}->pop_level();
}

######################################################################
##                                                                  ##
##                           LOGGING                                ##
##                                                                  ##
######################################################################

sub log($$$;$) {
    my $self = shift;

    my $level   = shift;
    my $message = shift;
    my $name    = shift;

    my $sinks = $sinks_of{ident $self};

    if ( defined($name)) {
        if ( ! defined($sinks->{$name}) ) {
            TeX::Logger::Error->throw( name => $name);
        }

        $sinks->{$name}->log($level, $message);
    } else {
        for my $name (keys %{ $sinks }) {
            if (defined($sinks->{$name})) {
                $sinks->{$name}->log($level, $message);
            }
        }
    }

    return;
}

sub fatal {
    my $self = shift;

    my $message = shift;
    my $name    = shift;

    $self->log(LOG_FATAL, $message, $name);

    if ( $die_on_fatal_of{ident $self} ) {
        TeX::Logger::Error->throw($message);
    }

    return;
}

sub error {
    my $self = shift;

    my $message = shift;
    my $name    = shift;

    $self->log(LOG_ERROR, $message, $name);

    return;
}

sub warn {
    my $self = shift;

    my $message = shift;
    my $name    = shift;

    $self->log(LOG_WARNING, $message, $name);

    return;
}

sub notify ($$;$) {
    my $self = shift;

    my $message = shift;
    my $name    = shift;

    $self->log(LOG_NORMAL, $message, $name);

    return;
}

sub verbose ($$;$) {
    my $self = shift;

    my $message = shift;
    my $name    = shift;

    $self->log(LOG_VERBOSE, $message, $name);

    return;
}

sub debug ($$;$) {
    my $self = shift;

    my $message = shift;
    my $name    = shift;

    $self->log(LOG_DEBUG, $message, $name);

    return;
}

######################################################################
##                                                                  ##
##                          CONFIGURATION                           ##
##                                                                  ##
######################################################################

sub batch_mode {
    my $self = shift;

    $self->delete_sink('notice');

    return;
}

sub set_debug($;$) {
    my $self = shift;

    my $debug = defined($_[0]) ? shift : 1;

    if ( $debug ) {
        $self->set_sink_level('notice', LOG_DEBUG);
    } else {
        $self->set_sink_level('notice', LOG_NORMAL);
    }
}

sub set_verbose($;$) {
    my $self = shift;

    my $verbose = defined($_[0]) ? shift : 1;

    if ( $verbose ) {
        $self->set_sink_level('notice', LOG_VERBOSE);
    } else {
        $self->set_sink_level('notice', LOG_NORMAL);
    }
}

sub set_quiet($;$) {
    my $self = shift;

    my $quiet = defined($_[0]) ? shift : 1;

    if ( $quiet ) {
        $self->set_sink_level('notice', LOG_WARNING);
    } else {
        $self->set_sink_level('notice', LOG_NORMAL);
    }
}

sub set_normal {
    my $self = shift;

    $self->set_sink_level('notice', LOG_NORMAL);
}

1;

__END__
