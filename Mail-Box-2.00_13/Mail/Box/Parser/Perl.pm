use strict;
use warnings;

package Mail::Box::Parser::Perl;
use base 'Mail::Box::Parser';

use List::Util 'sum';
use FileHandle;

our $VERSION = '2.00_13';

=head1 NAME

 Mail::Box::Parser::Perl - Reading messages from file using Perl

=head1 CLASS HIERARCHY

 Mail::Box::Parser::Perl
 is a Mail::Box::Parser
 is a Mail::Reporter

=head1 SYNOPSIS

=head1 DESCRIPTION

The C<Mail::Box::Parser::Perl> implements parsing of messages in Perl.
This may be a little slower than the C<C> based parser, but will also
work on platforms where no C compiler is available.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Parser::Perl> objects:

  MBP bodyAsFile FILEHANDLE [,CHA...   MBP popSeparator
  MBP bodyAsList [,CHARS [,LINES]]     MBP pushSeparator STRING
  MBP bodyAsString [,CHARS [,LINES]]   MBP readHeader WRAP
  MBP bodyDelayed [,CHARS [,LINES]]    MBP readSeparator OPTIONS
  MBP defaultParserType [CLASS]         MR report [LEVEL]
   MR errors                            MR reportAll [LEVEL]
  MBP foldHeaderLine LINE, LENGTH      MBP setPosition WHERE
  MBP inDosmode                        MBP start OPTIONS
   MR log [LEVEL [,STRINGS]]           MBP stop
  MBP new [OPTIONS]                     MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MBP = L<Mail::Box::Parser>

=head1 METHODS

=over 4

=cut

sub init(@)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $filename = $args->{filename};
    my $file     = new FileHandle $filename, $self->{MBP_mode};
    return unless $file;

    $self->{MBPP_file}       = $file;
    $self->{MBPP_filename}   = $filename;
    $self->{MBPP_seperator}  = $args->{seperator} || undef;
    $self->{MBPP_dosmode}    = 1;
    $self->{MBPP_separators} = [];

    $self->log(PROGRESS => "Opened folder from file $filename.");

    $self;
}

#------------------------------------------

sub closeFile()
{   my $self = shift;
    my $file = delete $self->{MBPP_file} || return;
    $file->close;

    delete $self->{MBPP_separators};
    $self;
}

#------------------------------------------

sub pushSeparator($)
{   my ($self, $sep) = @_;
    unshift @{$self->{MBPP_separators}}, $sep;
    $self->{MBPP_strip_gt}++ if $sep =~ /^From /;
    $self;
}

#------------------------------------------

sub popSeparator()
{   my $self = shift;
    my $sep  = shift @{$self->{MBPP_separators}};
    $self->{MBPP_strip_gt}++ if $sep =~ /^From /;
    $sep;
}
    
#------------------------------------------

sub _get_one_line()
{   my $self = shift;
    return delete $self->{MBPP_keep_line}
        if exists $self->{MBPP_keep_line};

    my $file = $self->{MBPP_file};

    $self->{MBPP_start_line} = tell $file;
    my $line = $file->getline || return;

    if($self->{MBPP_dosmode})
    {   if($line =~ s/\r\n$/\n/) {;}
        elsif($line !~ /\n$/)    {$line .= "\n"}
        else                     {delete $self->{MBPP_dosmode}}
    }

    $line;
}

#------------------------------------------

sub _file_position()
{   my $self = shift;
    
      exists $self->{MBPP_keep_line}
    ? $self->{MBPP_start_line}
    : tell $self->{MBPP_file};
}

#------------------------------------------

sub setPosition($)
{   my $self = shift;
    delete $self->{MBPP_keep_line};
    seek $self->{MBPP_file}, shift, 0;
}

#------------------------------------------

sub readHeader($$)
{   my $self = shift;
    my @ret  = $self->_file_position;

    while(my ($field, $content) = $self->_read_header_line)
    {   push @ret, $field, $content;
    }

    @ret;
}

#------------------------------------------

sub _read_header_line()
{   my $self = shift;
    my $line = $self->_get_one_line;

    return () if !defined $line || $line eq "\n";

    my ($name, $body) = split /\:\s*/, $line, 2;

    unless(defined $body)
    {   $self->log(WARNING => "Unexpected end of header:\n  $line");
        $self->{MBPP_keep_line} = $line;
        return $self;
    }

    $self->log(WARNING => "Blanks stripped after header fieldname: $name.")
        if $name =~ s/\s+$//;

    $self->log(WARNING => "Field $name is empty.")
        if $body eq "\n";

    # Do unfolding

    while(1)
    {   $line = $self->_get_one_line;

        if($line eq "\n")
        {   $self->{MBPP_keep_line} = $line;
            last;
        }

        unless($line =~ m/^\s/)
        {   $self->{MBPP_keep_line} = $line;
            last;
        }

        $body .= $line;
    }

    for($body)
    {   s/\s+/ /g;
        s/ $//;
    }

    ($name, $body);
}

#------------------------------------------

sub foldHeaderLine($$)
{   my ($self, $original, $wrap) = (shift, shift, shift);
    my @lines;
    my $pre = '';

    for($original)
    {   s/\s+/ /g;   # unfold
        s/\s+$//g;
        return $original if length $_ < $wrap;

        while(1)
        {   # Find last special char before wrap.
            $_ = $pre.$_;
            last if length $_ <= $wrap;

            my $find = reverse substr($_, 20, $wrap-20);
            my $blank= 0;
            my $pos  = index $find, ';';
            $pos     = index $find, ',' unless $pos >= 0;
            unless($pos >= 0)
            {   $pos = index $find, ' ';
                $blank = 1 if $pos >= 0;
            }
            $pos     = index $find, '.' unless $pos >= 0;

            if($pos >= 0) { $pos = 20+length($find)-$pos-$blank }
            else
            {   # Not found, so extend line.
                $pos = $wrap;
                while($pos < length)
                {   my $c = substr $_, $pos++, 1;
                    last if $c eq ';' || $c eq ',' || $c eq ' ' || $c eq '.';
                }
                $pos--;
            }
            push @lines, (substr $_, 0, $pos, '')."\n";
            $pre = '        ';
            s/^\s+//;
        }
        push @lines, "$_\n" if length $_;
    }

    @lines;
}

#------------------------------------------

sub inDosmode() {shift->{MBPP_dosmode}}

#------------------------------------------

sub _is_good_end(;$)
{   my ($self, $where) = @_;

    # No seps, then when have to trust it.
    my $sep = $self->{MBPP_separators}[0];
    return 1 unless defined $sep;

    my $here = $self->_file_position;
    if(defined $where)
    {   seek $self->{MBPP_file}, $where, 0;
        delete $self->{MBPP_keep_line};
    }

    # Found first non-empty line on specified location.
    my $line = $self->_get_one_line;
    $line    = $self->_get_one_line while defined $line && $line eq "\n";

    seek $self->{MBPP_file}, $here, 0;
    return 1 unless defined $line;

    substr($line, 0, length $sep) eq $sep;
}

#------------------------------------------

sub readSeparator()
{   my $self = shift;

    my $sep = $self->{MBPP_separators}[0];
    return () unless defined $sep;

    my $line = $self->_get_one_line;
    $line    = $self->_get_one_line while defined $line && $line eq "\n";
    return () unless defined $line;

    return ($self->{MBPP_start_line}, $line)
        if substr($line, 0, length $sep) eq $sep;

    $self->{MBPP_keep_line} = $line;
    ();
}

#------------------------------------------

sub _read_stripped_lines(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    $exp_lines    = -1 unless defined $exp_lines;
    my @seps      = @{$self->{MBPP_separators}};

    my @lines     = ();

    if(@seps)
    {   my $line = $self->_get_one_line;

  LINE: while(defined $line)
        {   foreach (@seps)
            {   last LINE if substr($line, 0, length $_) eq $_;
            }

            push @lines, $line;
            $line = $self->_get_one_line;
        }

        $self->{MBPP_keep_line} = $line if defined $line;

        if($exp_lines > 0 )
             { pop @lines while @lines > $exp_lines && $lines[-1] eq "\n" }
        else { pop @lines    if @lines              && $lines[-1] eq "\n" }
    }
    else
    {   # File without separators.
        while(@lines < $exp_lines)
        {   my $line = $self->_get_one_line || last;
            push @lines, $line;
        }
    }

    map { s/^\>(\>*From\s)/$1/ } @lines
        if $self->{MBPP_strip_gt};

    \@lines;
}

#------------------------------------------

sub _take_scalar($$)
{   my ($self, $begin, $end) = @_;
    my $file = $self->{MBPP_file};
    seek $file, $begin, 0;

    my $return;
    read $file, $return, $begin-$end;
    $return;
}

#------------------------------------------

sub bodyAsString(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    my $begin = $self->_file_position;

    if(!$self->{MBPP_dosmode} && !$self->{MBPP_strip_gt}
       && defined $exp_chars && $exp_chars>=0)
    {   # Get at once may be successful
        my $end = $begin + $exp_chars;

        return ($begin, $self->_take_scalar($begin, $end))
            if $self->_is_good_end($end);
    }

    my $lines = $self->_read_stripped_lines($exp_chars, $exp_lines);
    return () unless @$lines;

    return ($begin, join('', @$lines));
}


#------------------------------------------

sub bodyAsList(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    my $begin = $self->_file_position;

    my $lines = $self->_read_stripped_lines($exp_chars, $exp_lines);
    @$lines ? ($begin, @$lines) : ();
}

#------------------------------------------

sub bodyAsFile($;$$)
{   my ($self, $out, $exp_chars, $exp_lines) = @_;
    my $begin = $self->_file_position;

    my $lines = $self->_read_stripped_lines($exp_chars, $exp_lines);
    return () unless @$lines;

    $out->print($_) foreach @$lines;
    ($begin, scalar @$lines);
}

#------------------------------------------

sub bodyDelayed(;$$)
{   my ($self, $exp_chars, $exp_lines) = @_;
    my $begin = $self->_file_position;

    if(defined $exp_chars)
    {   my $end = $begin + $exp_chars;

        if($self->_is_good_end($end))
        {   seek $self->{MBPP_file}, $begin+$exp_chars, 0;
            return ($begin, $exp_chars, $exp_lines);
        }
    }

    my $lines = $self->_read_stripped_lines($exp_chars, $exp_lines);
    return () unless @$lines;

    ($begin, sum(map {length} @$lines), scalar @$lines);
}

#------------------------------------------

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_13.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;