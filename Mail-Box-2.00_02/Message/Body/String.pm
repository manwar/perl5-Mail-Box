use strict;
use warnings;

package Mail::Message::Body::String;
use base 'Mail::Message::Body';

our $VERSION = '2.00_02';

use Carp;
use IO::Scalar;

=head1 NAME

Mail::Message::Body::String - Body of a Mail::Message stored as single string

=head1 SYNOPSIS

   my $body  = $msg->body;
   my $text  = $body->string;
   my @text  = $body->lines;
   my FileHandle $file = $body->file;
   $body->print(\*FILE);

=head1 DESCRIPTION

READ C<Mail::Message::Body> FIRST. This manual-page only describes the
extentions to the default body functionality.

The body (content) of a message can be stored in various ways.  In this
manual-page you find the description of extra functionality you have
when a message is stored in a single scalar.  

Storing a whole message in one string is only a smart choice when the
content is small or encoded.  You can treat the body as if the data
is stored in lines or an external file, but this will be slower.

=head1 GENERAL METHODS

=over 4

=cut

#------------------------------------------

sub _data_from_file(@_)
{   my ($self, $fh) = @_;
    my $data;

    if(ref $fh eq 'GLOB')
    {   local $/ = undef;
        $data = <$fh>;
    }
    else
    {   $data = join '', $fh->getlines;
    }

    $self->{MMBS_scalar} = \$data;
}

sub _data_from_lines(@_)
{   my ($self, $lines) = @_;
    my $ref;

    if(@$lines==1)
    {   $ref = \($lines->[0]);
    }
    else
    {   $ref = \(join '', @$lines);
        $self->{MMBS_nrlines} = @$lines;
    }

    $self->{MMBS_scalar} = $ref;
}

#------------------------------------------

sub data(@)
{   my $self = shift;
    delete $self->{MMBS_nrlines};
    $self->SUPER::data(@_);
}

#------------------------------------------

sub string() { ${shift->{MMBS_scalar}} }

#------------------------------------------

sub lines()
{   my @lines = split /(?<=\n)/, ${shift->{MMBS_scalar}};
    wantarray ? @lines : \@lines;
}

#------------------------------------------
# Only compute it once, if needed.  The scalar contains lines, so will
# have a \n even at the end.

sub nrLines()
{   my $self = shift;
    return $self->{MMBS_nrlines} if exists $self->{MMBS_nrlines};

    my $nrlines = 0;
    for(${$self->{MMBS_scalar}} )
    {   $nrlines++ while /\n/g;
    }

    $self->{MMBS_nrlines} = $nrlines;
}


sub size() { length ${shift->{MMBS_scalar}} }

#------------------------------------------

sub file() { IO::Scalar->new(shift->{MMBS_scalar}) }

#------------------------------------------

=item read FILE [,LENGTH]

Read the body from the FILE.  The result is one scalar.  The lines of
the body will have to be processed one after the other, to fix some
things up, like line-endings and the escaped 'From' sequences in
Mbox folders.

The LENGTH is the estimated number of bytes which are in the body, or
C<undef> when this is not known.

=cut

sub read($$)
{   my ($self, $file, $length) = @_;
    Mail::Box::Parser::body_string($file, $length || -1);
}

#------------------------------------------

=item print [FILE]

=cut

sub print(;$)
{   my $self = shift;
    my $fh   = shift || \*STDOUT;
    $fh->print(${$self->{MMBS_scalar}});
}

#------------------------------------------

=back

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is alpha version 1.318, and far from complete.  Please
contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::Message::Body>
L<Mail::Box::Manager>

=cut

1;