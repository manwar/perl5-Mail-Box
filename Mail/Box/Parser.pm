use strict;
use warnings;

package Mail::Box::Parser;
use base 'Mail::Reporter';
use Carp;

=head1 NAME

Mail::Box::Parser - reading and writing messages

=head1 SYNOPSIS

=head1 DESCRIPTION

The Mail::Box::Parser manages the parsing of folders.  Usually, you won't
need to know anything about this module, except the options which are
involved with this code.

There are two implementations of this module planned:

=over 4

=item * Mail::Box::Parser::Perl

A slower parser which only uses plain Perl.  This module is a bit slower,
and does less checking and less recovery.

=item * Mail::Box::Parser::C

A fast parser written in C<C>.  However, this parser is still under
development.

=back

On the moment the C parser comes available, and a C compiler is available
on your system, it will be used automatically.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

(Class method)  Create a parser object which can handle one file.  For
mbox-like mailboxes, this object can be used to read a whole folder.  In
case of MH-like mailboxes, each message is contained in a single file,
so each message has its own parser object.

=option  filename FILENAME
=default filename <required>

(Required) The name of the file to be read.

=option  file FILE-HANDLE
=default file undef

Any C<IO::File> or C<GLOB> which can be used to read the data from.  In
case this option is specified, the C<filename> is informational only.

=option  mode OPENMODE
=default mode 'r'

File-open mode, which defaults to C<'r'>, which means `read-only'.
See C<perldoc -f open> for possible modes.  Only applicable 
when no C<file> is specified.

=cut

sub new(@)
{   my $class       = shift;

    return $class->defaultParserType->new(@_)   # bootstrap right parser
        if $class eq __PACKAGE__;

    my $self = $class->SUPER::new(@_) or return;
    $self->start;     # new includes init.
}

sub init(@)
{   my ($self, $args) = @_;

    $args->{trace} ||= 'WARNING';

    $self->SUPER::init($args);

    $self->{MBP_separator} = $args->{separator} || '';
    $self->{MBP_mode}      = $args->{mode}      || 'r';

    my $filename =
    $self->{MBP_filename}  = $args->{filename}
        or confess "Filename obligatory to create a parser.";

    $self->takeFileInfo;
    $self->log(NOTICE => "Created parser for $filename");

    $self;
}

#------------------------------------------

=head2 The Parser

=cut

#------------------------------------------

=method defaultParserType [CLASS]

(Class or instance method) Returns the parser to be used to parse all subsequent
messages, possibly first setting the parser using the optional argument.
Usually, the parser is autodetected; the C<C>-based parser will be used
when it can be, and the Perl-based parser will be used otherwise.

The CLASS argument allows you to specify a package name to force a
particular parser to be used (such as your own custom parser). You have
to C<use> or C<require> the package yourself before calling this method
with an argument. The parser must be a sub-class of Mail::Box::Parser.

=cut

my $parser_type;

sub defaultParserType(;$)
{   my $class = shift;

    # Select the parser manually?
    if(@_)
    {   $parser_type = shift;
        return $parser_type if $parser_type->isa( __PACKAGE__ );

        confess "Parser $parser_type does not extend "
              . __PACKAGE__ . "\n";
    }

    # Already determined which parser we want?
    return $parser_type if $parser_type;

    # Try to use C-based parser.
#  eval 'require Mail::Box::Parser::C';
#warn "C-PARSER errors $@\n" if $@;
#   return $parser_type = 'Mail::Box::Parser::C'
#       unless $@;

    # Fall-back on Perl-based parser.
    require Mail::Box::Parser::Perl;
    $parser_type = 'Mail::Box::Parser::Perl';
}

#------------------------------------------

=method start OPTIONS

Start the parser.  The parser is automatically started when the parser is
created, however can be stopped (see stop()).  During the start,
the file to be parsed will be opened.

=option  trust_file BOOLEAN
=default trust_file <false>

When we continue with the parsing of the folder, and the modification-time
(on operating-systems which support that) or size changed, the parser
will refuse to start, unless this option is true.

=cut

sub start(@)
{   my ($self, %args) = @_;

    my $filename = $self->filename;

    unless($args{trust_file})
    {   if($self->fileChanged)
        {   $self->log(ERROR => "File $filename changed, refuse to continue.");
            return;
        }
    }

    $self->log(NOTICE => "Open file $filename to be parsed");
    $self;
}

#------------------------------------------

=method stop

Stop the parser, which will include a close of the file.  The lock on the
folder will not be removed (is not the responsibility of the parser).

=cut

sub stop()
{   my $self     = shift;
    my $filename = $self->filename;

    $self->log(WARNING => "File $filename changed during access.")
       if $self->fileChanged;

    $self->log(NOTICE => "Close parser for file $filename");
    $self;
}

#------------------------------------------

=method takeFileInfo

Capture some data about the file being parsed, to be compared later.

=cut

sub takeFileInfo()
{   my $self     = shift;
    my $filename = $self->filename;
    @$self{ qw/MBP_size MBP_mtime/ } = (stat $filename)[7,9];
}

#------------------------------------------

=method fileChanged

Returns whether the file which is parsed has changed after the last
time takeFileInfo() was called.

=cut

sub fileChanged()
{   my $self = shift;
    my $filename       = $self->filename;
    my ($size, $mtime) = (stat $filename)[7,9];
    return 0 unless $size;

      $size != $self->{MBP_size} ? 0
    : !defined $mtime            ? 1
    : $mtime != $self->{MBP_mtime};
}
    
#------------------------------------------

=method filename

Returns the name of the file this parser is working on.

=cut

sub filename() {shift->{MBP_filename}}

#------------------------------------------

=head2 Parsing

=cut

#------------------------------------------

=method filePosition [POSITION]

Returns the location of the next byte to be used in the file which is
parsed.  When a POSITION is specified, the location in the file is
moved to the indicated spot first.

=cut

sub filePosition(;$) {shift->NotImplemented}

#------------------------------------------

=method pushSeparator STRING|REGEXP

Add a boundary line.  Separators tell the parser where to stop reading.
A famous separator is the C<From>-line, which is used in Mbox-like
folders to separate messages.  But also parts (I<attachments>) is a
message are divided by separators.

The specified STRING describes the start of the separator-line.  The
REGEXP can specify a more complicated format.

=cut

sub pushSeparator($) {shift->notImplemented}

#------------------------------------------

=method popSeparator

Remove the last-pushed separator from the list which is maintained by the
parser.  This will return C<undef> when there is none left.

=cut

sub popSeparator($) {shift->notImplemented}

#------------------------------------------

=method readSeparator OPTIONS

Read the currently active separator (the last one which was pushed).  The
line (or C<undef>) is returned.  Blank-lines before the separator lines
are ignored.

The return are two scalars, where the first gives the location of the
separator in the file, and the second the line which is found as
separator.  A new separator is activated using the pushSeparator() method.

=cut

sub readSeparator($) {shift->notImplemented}

#------------------------------------------

=method readHeader

Read the whole message-header and return it as list
C<< field => value, field => value >>.  Mind that some fields will
appear more than once.

The first element will represent the position in the file where the
header starts.  The follows the list of header field names and bodies.

=example

 my ($where, @header) = $parser->readHeader;

=cut

sub readHeader()    {shift->notImplemented}

#------------------------------------------

=method bodyAsString [,CHARS [,LINES]]

Try to read one message-body from the file.  Optionally, the predicted number
of CHARacterS and/or LINES to be read can be supplied.  These values may be
C<undef> and may be wrong.

The return is a list of three scalars, the location in the file
where the body starts, where the body ends, and the string containing the
whole body.

=cut

sub bodyAsString() {shift->notImplemented}

#------------------------------------------

=method bodyAsList [,CHARS [,LINES]]

Try to read one message-body from the file.  Optionally, the predicted number
of CHARacterS and/or LINES to be read can be supplied.  These values may be
C<undef> and may be wrong.

The return is a list of scalars, each containing one line (including
line terminator), preceded by two integers representing the location
in the file where this body started and ended.

=cut

sub bodyAsList() {shift->notImplemented}

#------------------------------------------

=method bodyAsFile FILEHANDLE [,CHARS [,LINES]]

Try to read one message-body from the file, and immediately write
it to the specified file-handle.  Optionally, the predicted number
of CHARacterS and/or LINES to be read can be supplied.  These values may be
C<undef> and may be wrong.

The return is a list of three scalars: the location of the body (begin
and end) and the number of lines in the body.

=cut

sub bodyAsFile() {shift->notImplemented}

#------------------------------------------

=method bodyDelayed [,CHARS [,LINES]]

Try to read one message-body from the file, but the data is skipped.
Optionally, the predicted number of CHARacterS and/or LINES to be skipped
can be supplied.  These values may be C<undef> and may be wrong.

The return is a list of four scalars: the location of the body (begin and
end), the size of the body, and the number of lines in the body.  The
number of lines may be C<undef>.

=cut

sub bodyDelayed() {shift->notImplemented}

#------------------------------------------

=method lineSeparator

Returns the character or characters which are used to separate lines
in the folder file.  This is based on the first line of the file.
UNIX systems use a single LF to separate lines.  Windows uses a CR and
a LF.  Mac uses CR.

=cut

sub lineSeparator() {shift->{MBP_linesep}}

#------------------------------------------

sub DESTROY
{   my $self = shift;
    $self->SUPER::DESTROY;
    $self->stop;
}

#------------------------------------------

1;
