package TeX::Logger::Sink;

use strict;
use warnings;

use version; our $VERSION = qv '1.0.0';

use base qw(Exporter);

our %EXPORT_TAGS = (constants => [ qw(LOG_FATAL 
                                      LOG_ERROR 
                                      LOG_WARNING
                                      LOG_NORMAL
                                      LOG_VERBOSE 
                                      LOG_DEBUG 
                                   ) ]);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{constants} } );

our @EXPORT;

use IO::Handle;
use IO::File;

use UNIVERSAL;

use Class::Std;

use Exception::Class qw(TeX::Logger::Sink::Error);

######################################################################
##                                                                  ##
##                            CONSTANTS                             ##
##                                                                  ##
######################################################################

use constant {
    LOG_FATAL   => 0,
    LOG_ERROR   => 1,
    LOG_WARNING => 2,
    LOG_NORMAL  => 3,
    LOG_VERBOSE => 4,
    LOG_DEBUG   => 5,
};

my @LEVEL_NAME;

$LEVEL_NAME[LOG_FATAL]   = 'FATAL';
$LEVEL_NAME[LOG_ERROR]   = 'ERROR';
$LEVEL_NAME[LOG_WARNING] = 'WARNING';
$LEVEL_NAME[LOG_NORMAL]  = 'NORMAL';
$LEVEL_NAME[LOG_VERBOSE] = 'VERBOSE';
$LEVEL_NAME[LOG_DEBUG]   = 'DEBUG';

######################################################################
##                                                                  ##
##                         ATTRIBUTES                               ##
##                                                                  ##
######################################################################

# handle_of can be any of: 
#    1. A filename (string)
#    2. A filehandle (e.g. *STDOUT or a FileHandle object)
#    3. A reference to a block of code.
#    4. A reference to a scalar.
# don't define set_handle here because it needs special handling.

my %handle_of :ATTR(:get<handle>  :init_arg<handle> :default<*STDERR> );
my %level_of  :ATTR(:name<level>  :default<3> );
my %mode_of   :ATTR(:name<mode>   :default<0664> );
my %prefix_of :ATTR(:name<prefix> :default<""> );
my %use_level_prefix_of :ATTR(:name<use_level_prefix> :default<0>);

# private, no getter or setter:

# This is the handle we actually print to. Its relationship to
# handle_of depends on the type of handle_of it is dealing with.

my %private_handle_of :ATTR; 

# used by push_level and pop_level

my %level_stack_of :ATTR;

# flag to tell set_handle whether to close previous handle

my %got_open_filehandle_of :ATTR(:default<0>);

# flag to tell whether to append existing file (if given a path)
# This is ignored if given a filehandle or code ref.
# Default is to overwrite, NOT append.

my %append_of :ATTR(:init_arg<append> :default<0>);

######################################################################
##                                                                  ##
##                           SUBROUTINES                            ##
##                                                                  ##
######################################################################

# START may throw any exceptions thrown by open_handle.

sub START {
    my ($self, $ident, $arg_ref) = @_;

    $level_stack_of{$ident}= [];

    $self->open_handle();

    return;
}

sub DEMOLISH {
    my $self = shift;

    $self->close_handle();

    return;
}

# throws a variety of exceptions, some of which come from things it calls.

sub open_handle :RESTRICTED {
    my $self = shift;

    my $fail_if_undef = shift;

    my $ident = ident $self;

    my $handle = $handle_of{$ident};

    # If handle isn't defined, throw exception if flag is set.

    if ( $fail_if_undef && !defined($handle)) {
        TeX::Logger::Sink::Error->throw("Attempt to open undefined handle");
    }

    # If code ref, just use it as is.

    if ( UNIVERSAL::isa($handle, 'CODE') ) {
        $private_handle_of{$ident} = $handle;

        return;
    }

    $got_open_filehandle_of{$ident} = 0;

    if (UNIVERSAL::isa($handle, 'SCALAR')) {
        my $open_mode = $append_of{$ident} ? '>>:utf8' : '>:utf8';

        ## open() sometimes (!) complains if the handle points to an
        ## undefined scalar.

        $$handle = '' unless defined $$handle;

        open(my $fh, $open_mode, $handle);

        $private_handle_of{$ident} = $fh;

        return;
    }

    # If $handle is an open filehandle, use its fileno for IO::Handle

    if ( defined(fileno($handle)) && fileno($handle) > 0 ) {
        # it's an already-open filehandle

        $private_handle_of{$ident} = new IO::Handle();

        my $private_handle = $private_handle_of{$ident};

        unless ( $private_handle->fdopen(fileno($handle), "w") ) {
            TeX::Logger::Sink::Error->throw("Can't open file descriptor: $!");
        }
        
        # This is so that close_handle knows not to close the stream.

        $got_open_filehandle_of{$ident} = 1;

        return;
    } else {
        # If we got this far, then $handle should be a string.

        my $open_mode = '>';

        $open_mode = '>>' if $append_of{$ident};

        unless ( $private_handle_of{$ident} = new IO::File($handle, $open_mode)) {
            TeX::Logger::Sink::Error->throw("Can't open handle to string: $!");
          }
    }

    # since we're logging, always autoflush.

    $private_handle_of{$ident}->autoflush(1);

}

sub close_handle :RESTRICTED {
    my $self = shift;

    my $oldhandle = $handle_of{ident $self};
    my $mode      = $mode_of{ident $self};

    # close existing handle if it's open
    unless ( $got_open_filehandle_of{ident $self} || 
            UNIVERSAL::isa($oldhandle, 'CODE') ) {
        my $private_handle = $private_handle_of{ident $self};

        if ( defined($private_handle) && $private_handle->opened() ) { 
            $private_handle->close();
        }

        # set mode of file if mode is defined.  If we got to here,
        # oldhandle should be a string rather than filehandle

        if ( defined($mode) && $mode =~ /^\d\d\d\d?$/ ) {
            if ( $mode =~ /^\d\d\d$/ ) {
                $mode = '0'.$mode;
            }

            chmod $mode, $oldhandle;
        }
    }

    return;
}

# Special setter for handle.

sub set_handle($$) {
    my $self = shift;

    my $newhandle = shift;

    # close existing handle
    $self->close_handle();

    # now set the new value and open it.

    $handle_of{ident $self} = $newhandle;

    $self->open_handle();

    return;
}

sub push_level($$) {
    my $self = shift;

    my $level = shift;

    if ( $level =~ /\D/ || $level > LOG_DEBUG ) {
        TeX::Logger::Sink::Error->throw("Invalid log level $level");
    }

    my $ident = ident $self;

    push @{$level_stack_of{$ident}}, $level_of{$ident};

    $level_of{$ident} = $level;

    return;
}

sub pop_level($) {
    my $self = shift;

    if ( @{ $level_stack_of{ident $self} } <= 0) {
        return $level_of{ident $self};
    }

    $level_of{ident $self} = pop @{ $level_stack_of{ident $self} };

    return $level_of{ident $self};
}


sub log($$$) {
    my $self = shift;

    my $level   = shift;
    my $message = shift;

    return if $level =~ /\D/;
    return if $level > $level_of{ident $self};

    if (UNIVERSAL::isa($message, 'ARRAY')) {
        $message = join '', @{ $message };
    }

    my $prefix = $prefix_of{ident $self} || '';

    if (length($prefix) == 0 && $self->get_use_level_prefix()) {
        $prefix = $LEVEL_NAME[$level] . ":"
    }

    if ( $prefix =~ /\D/ ) {
        $message =~ s/^/$prefix /smxg;
    } elsif ( $prefix ) {
        # use numeric flags to indicate some sort of default prefix values?
    }

    my $private_handle = $private_handle_of{ident $self};

    if (UNIVERSAL::isa($private_handle, 'CODE')) {
        $private_handle->($message);

        return;
    }

    $private_handle->print($message);

    if ( $private_handle->error() ) {
        my $name = $handle_of{ident $self};

        if ( ref($name) ) {
            $name = ref($name);
        } elsif ( fileno($name)) {
            $name = fileno($name);
        }

        TeX::Logger::Sink::Error->throw("TeX::Logger::Sink $name error: $!");
    }

    return;    
}

1;

__END__
