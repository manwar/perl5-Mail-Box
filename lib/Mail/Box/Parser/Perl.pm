use strict;
use warnings;

package Mail::Box::Parser::Perl;
use base 'Mail::Box::Parser';

use Mail::Message::Field;
use List::Util 'sum';
use IO::File;

=chapter NAME

Mail::Box::Parser::Perl - reading messages from file using Perl

=chapter SYNOPSIS

=chapter DESCRIPTION

The C<Mail::Box::Parser::Perl> implements parsing of messages
in Perl.  This may be a little slower than the C<C> based parser
M<Mail::Box::Parser::C>, but will also work on platforms where no C
compiler is available.

=chapter METHODS

=c_method new OPTIONS

=option  trusted BOOLEAN
=default trusted <false>

Is the input from the file to be trusted, or does it require extra
tests.  Related to M<Mail::Box::new(trusted)>.

=option  fix_header_errors BOOLEAN
=default fix_header_errors <false>

When header errors are detected, the parsing of the header will
be stopped.  Other header lines will become part of the body of
the message.  Set this flag to have the erroneous line added to
the previous header line.

=cut

sub init(@)
{   my ($self, $args) = @_;

    $self->SUPER::init($args) or return;

    $self->{MBPP_trusted} = $args->{trusted};
    $self->{MBPP_fix}     = $args->{fix_header_errors};
    $self;
}


#------------------------------------------

sub pushSeparator($)
{   my ($self, $sep) = @_;
    unshift @{$self->{MBPP_separators}}, $sep;
    $self->{MBPP_strip_gt}++ if substr($sep, 0, 5) eq 'From ';
    $self;
}

#------------------------------------------

sub popSeparator()
{   my $self = shift;
    my $sep  = shift @{$self->{MBPP_separators}};
    $self->{MBPP_strip_gt}-- if substr($sep, 0, 5) eq 'From ';
    $sep;
}
    
#------------------------------------------

sub filePosition(;$)
{   my $self = shift;
    @_ ? $self->{MBPP_file}->seek(shift, 0) : $self->{MBPP_file}->tell;
}

my $empty = qr/^[\015\012]*$/;

#------------------------------------------

=method readHeader

=warning Unexpected end of header in $source: $line

While parsing a message from the specified source (usually a file name),
the parser found a syntax error.  According to the MIME specification in the
RFCs, each header line must either contain a colon, or start with a blank
to indicate a folded field.  Apparently, this header contains a line which
starts on the first position, but not with a field name.

By default, parsing of the header will be stopped.  If there are more header
lines after the erroneous line, they will be added to the body of the message.
In case of new(fix_headers) set, the parsing of the header will be continued.
The erroneous line will be added to the preceding field.

=cut

sub readHeader()
{   my $self  = shift;
    my $file  = $self->{MBPP_file};

    my $start = $file->tell;
    my @ret   = ($start, undef);
    my $line  = $file->getline;

LINE:
    while(defined $line)
    {   last if $line =~ $empty;
        my ($name, $body) = split /\s*\:\s*/, $line, 2;

        unless(defined $body)
        {   $self->log(WARNING =>
                "Unexpected end of header in ".$self->filename.":\n $line");

            if(@ret && $self->fixHeaderErrors)
            {   $ret[-1][1] .= ' '.$line;  # glue erroneous line to previous field
                $line = $file->getline;
                next LINE;
            }
            else
            {   $file->seek(-length $line, 1);
                last LINE;
            }
        }

        $body = "\n" unless length $body;

        # Collect folded lines
        while($line = $file->getline)
        {   $line =~ m!^[ \t]! ? ($body .= $line) : last;
        }

        $body =~ s/\015//g;
        push @ret, [ $name, $body ];
    }

    $ret[1]  = $file->tell;
    @ret;
}

#------------------------------------------

sub _is_good_end($)
{   my ($self, $where) = @_;

    # No seps, then when have to trust it.
    my $sep = $self->{MBPP_separators}[0];
    return 1 unless defined $sep;

    my $file = $self->{MBPP_file};
    my $here = $file->tell;
    $file->seek($where, 0);

    # Find first non-empty line on specified location.
    my $line = $file->getline;
    $line    = $file->getline while defined $line && $line =~ $empty;

    # Check completed, return to old spot.
    $file->seek($here, 0);
    return 1 unless defined $line;

    substr($line, 0, length $sep) eq $sep
    && ($sep !~ m/^From / || $line =~ m/ (19[789]|20[01])\d\b/ );
}

#------------------------------------------

sub readSeparator()
{   my $self = shift;

    my $sep   = $self->{MBPP_separators}[0];
    return () unless defined $sep;

    my $file  = $self->{MBPP_file};
    my $start = $file->tell;

    my $line  = $file->getline;
    while(defined $line && $line =~ $empty)
    {   $start   = $file->tell;
        $line    = $file->getline;
    }

    return () unless defined $line;

    $line     =~ s/[\012\015\n]+$/\n/g;
    return ($start, $line)
        if substr($line, 0, length $sep) eq $sep;

    $file->seek($start, 0);
    ();
}


#------------------------------------------

sub _read_stripped_lines(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    $exp_lines  = -1 unless defined $exp_lines;
    my @seps    = @{$self->{MBPP_separators}};

    my $file    = $self->{MBPP_file};
    my @lines   = ();

    if(@seps && $self->{MBPP_trusted})
    {   my $sep  = $seps[0];
        my $l    = length $sep;

        while(1)
        {   my $where = $file->tell;
            my $line  = $file->getline or last;

            if(   substr($line, 0, $l) eq $sep
               && (   substr($sep, 0, 5) ne 'From '
                   || $line =~ m/ (?:19[789]\d|20[01]\d)/
                  )
               )
            {   $file->seek($where, 0);
                last;
            }

            push @lines, $line;
        }
    }
    elsif(@seps)
    {   

  LINE: while(1)
        {   my $where = $file->getpos;
            my $line  = $file->getline or last;

            foreach my $sep (@seps)
            {   next if substr($line, 0, length $sep) ne $sep;
                next if substr($sep, 0, 5) eq 'From '
                       && $line !~ m/ (?:19[789]\d|20[01]\d)/;

                $file->setpos($where);
                last LINE;
            }

            $line =~ s/\015$//;
            push @lines, $line;
        }
    }
    else
    {   # File without separators.
        @lines = $file->getlines;
    }

    my $end = $file->tell;
    if($exp_lines > 0 )
    {    while(@lines > $exp_lines && $lines[-1] =~ $empty)
         {   $end -= length $lines[-1];
             pop @lines;
         }
    }
    else
    {    if(@lines && $lines[-1] =~ $empty)
         {   $end -= length $lines[-1];
             pop @lines;
         }
    }

    map { s/^\>(\>*From\s)/$1/ } @lines
        if $self->{MBPP_strip_gt};

    $end, \@lines;
}

#------------------------------------------

sub _take_scalar($$)
{   my ($self, $begin, $end) = @_;
    my $file = $self->{MBPP_file};
    $file->seek($begin, 0);

    my $return;
    $file->read($return, $end-$begin);
    $return =~ s/\015//g;
    $return;
}

#------------------------------------------

sub bodyAsString(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    my $file  = $self->{MBPP_file};
    my $begin = $file->tell;

    if(defined $exp_chars && $exp_chars>=0)
    {   # Get at once may be successful
        my $end = $begin + $exp_chars;

        if($self->_is_good_end($end))
        {   my $body = $self->_take_scalar($begin, $end);
            $body =~ s/^\>(\>*From\s)/$1/gm if $self->{MBPP_strip_gt};
            return ($begin, $file->tell, $body);
        }
    }

    my ($end, $lines) = $self->_read_stripped_lines($exp_chars, $exp_lines);
    return ($begin, $end, join('', @$lines));
}


#------------------------------------------

sub bodyAsList(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    my $file  = $self->{MBPP_file};
    my $begin = $file->tell;

    my ($end, $lines) = $self->_read_stripped_lines($exp_chars, $exp_lines);
    ($begin, $end, @$lines);
}

#------------------------------------------

sub bodyAsFile($;$$)
{   my ($self, $out, $exp_chars, $exp_lines) = @_;
    my $file  = $self->{MBPP_file};
    my $begin = $file->tell;

    my ($end, $lines) = $self->_read_stripped_lines($exp_chars, $exp_lines);

    $out->print($_) foreach @$lines;
    ($begin, $end, scalar @$lines);
}

#------------------------------------------

sub bodyDelayed(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    my $file  = $self->{MBPP_file};
    my $begin = $file->tell;

    if(defined $exp_chars)
    {   my $end = $begin + $exp_chars;

        if($self->_is_good_end($end))
        {   $file->seek($end, 0);
            return ($begin, $end, $exp_chars, $exp_lines);
        }
    }

    my ($end, $lines) = $self->_read_stripped_lines($exp_chars, $exp_lines);
    my $chars = sum(map {length} @$lines);
    ($begin, $end, $chars, scalar @$lines);
}

#------------------------------------------

sub openFile($)
{   my ($self, $args) = @_;
    my $fh = $args->{file} || IO::File->new($args->{filename}, $args->{mode});

    return unless $fh;
    $self->{MBPP_file}       = $fh;

    binmode $fh, ':raw'
       if ref($fh) eq 'GLOB' || $fh->can('BINMODE');

    $self->{MBPP_separators} = [];

    # Prepare the first line.
    $self->{MBPP_start_line} = 0;

    my $line  = $fh->getline || return $self;

    $line     =~ s/[\012\015]+$/\n/;
    $self->{MBP_linesep}     = $1;
    $fh->seek(0, 0);

#   binmode $fh, ':crlf' if $] < 5.007;  # problem with perlIO
    $self;
}

#------------------------------------------

sub closeFile()
{   my $self = shift;

    delete $self->{MBPP_separators};
    delete $self->{MBPP_strip_gt};

    my $file = delete $self->{MBPP_file} or return;
    $file->close;
    $self;
}
#------------------------------------------

=section The parser

=method fixHeaderErrors [BOOLEAN]

If set to C<true>, parsing of a header will not stop on an error, but
attempt to add the erroneous this line to previous field.  Without BOOLEAN,
the current setting is returned.

=example

 $folder->parser->fixHeaderErrors(1);
 my $folder = $mgr->open('folder', fix_header_errors => 1);

=cut

sub fixHeaderErrors(;$)
{   my $self = shift;
    @_ ? ($self->{MBPP_fix} = shift) : $self->{MBPP_fix};
}

#------------------------------------------

1;