use strict;
use warnings;

package Mail::Message::Field;

use base 'Mail::Reporter';
use Mail::Box::Parser;

use Carp;
use List::Util 'sum';

our $VERSION = '2.00_13';
our %_structured;

use overload qq("") => sub { $_[0]->body }
           , '+0'   => 'toInt'
           , bool   => sub {1}
           , cmp    => sub { $_[0]->body cmp "$_[1]" }
           , '<=>'  => sub { $_[2]
                           ? $_[1]        <=> $_[0]->toInt
                           : $_[0]->toInt <=> $_[1]
                           }
           , fallback => 1;


my $crlf = "\015\012";

=head1 NAME

Mail::Message::Field - one line of a Mail::Message header

=head1 CLASS HIERARCHY

 Mail::Message::Field
 is a Mail::Reporter

=head1 SYNOPSIS

 my $field = Mail::Message::Field->new(From => 'me@example.com');
 print $field->name;
 print $field->body;
 print $field->comment;
 $field->print(\*STDOUT);
 print $field->toString;
 print "$field\n";
 print $field->attribute('charset') || 'us-ascii';

=head1 DESCRIPTION

The object stores one header-line, and facilitates access routines to
that line.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Field> objects:

      attribute NAME [, VALUE]             nrLines
      body                                 print FILEHANDLE
      clone                             MR report [LEVEL]
      comment                           MR reportAll [LEVEL]
   MR errors                               setWrapLength CHARS
      isStructured                         size
   MR log [LEVEL [,STRINGS]]               toInt
      name                                 toString
      new ...                           MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

Prefixed methods are described in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

#------------------------------------------

=item new LINE [,ARRAY-OF-OPTIONS]

=item new NAME, BODY [,COMMENT [, OPTIONS]]

Create a new header-object.  Specify the whole header-LINE at once, and
it will be split-up for you.  I case you already have the parts of the
header-line, you may specify them.

In structured fields (a list of pre-defined fields are considered
to have a well-described format, checked with the C<isStructured> method)
everything behind a semi-color is officially a COMMENT.  The comment is
often (ab)used to supply extra information about the body information.

When the field you specify is structured, and you do not specify a comment
yourself, it will be stripped from the LINE or BODY for you.

To keep the communication overlead low (there are too many of these
field-objects to be created), the OPTIONS may be specified as last
argument to C<new>, but as reference to an array.  The following
options are available:

 OPTIONS      DESCRIBED IN          DEFAULT
 log          Mail::Reporter        'WARNINGS'
 trace        Mail::Reporter        'WARNINGS'

Examples:

   my @options = (log => 'NOTICE', trace => 'NONE');
   my $mime = Mail::Message::Field->new(
       'Content-Type: text/plain; charset=US-ASCII', \@options);

   my $mime = Mail::Message::Field->new(
       Content-Type => 'text/plain; charset=US-ASCII');

   my $mime = Mail::Message::Field->new(
       Content-Type => 'text/plain', 'charset=US-ASCII');

But, more often, you would call

   my $head = Mail::Message::Head->new;
   $head->add(Content-Type => 'text/plain; charset=US-ASCII');

which implicitly calls this constructor (when needed).

=cut

sub new($;$$@)
{
    my $class  = shift;

    my $create;
       if(@_==2 && ref $_[1]) { $create = [ shift ]; @_ = @{(shift)} }
    elsif(@_>=3)              { $create = [splice @_, 0, 3] }
    elsif(@_==2 || @_==1)     { $create = [@_]; @_ = () }
    else                      {confess}

    $class->SUPER::new(@_, create => $create);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my ($name, $body, $comment) = @{$args->{create}};

    #
    # Compose the body.
    #

    if(!defined $body)
    {   # must be one line of a header.
        ($name, $body) = split /\:\s*/, $name, 2;

        unless($body)
        {   $self->log(ERROR => "No colon in headerline: $name");
            $body = '';
        }
    }
    elsif($name =~ m/\:/)
    {   $self->log(ERROR => "A header-name cannot contain a colon in $name.");
        return undef;
    }

    $self->log(WARNING=> "Header-field name contains illegal character: $name.")
        if $name =~ m/[^\041-\176]/;

    $body =~ s/\s*\015?\012$//;

    #
    # Take the comment.
    #

    if(defined $comment && length $comment)
    {   # A comment is defined, so shouldn't be in body.
        confess "A header-body cannot contain a semi-colon in $body."
            if $body =~ m/\;/;
    }
    elsif(__PACKAGE__->isStructured($name))
    {   # try strip comment from field-body.
        $comment = $body =~ s/\s*\;\s*(.*)$// ? $1 : undef;
    }

    #
    # Create the object.
    #

    @$self{ qw/MMF_name MMF_body MMF_comment/ } = ($name, $body, $comment);
    $self;
}

#------------------------------------------

=item clone

Create a copy of this field object.

=cut

# This is a rather blunt appoach: no nice construction via new(), however
# it is called extremely often for one clone()... must be fast!

sub clone()
{   my $self = shift;
    my %new  = %$self;
    bless \%new, ref $self;
}

#------------------------------------------

=item name

Returns the name of this field, with all characters lower-cased for
ease of comparison.

=cut

sub name() { lc shift->{MMF_name} }

#------------------------------------------

=item body

Returns the body of the field, unmodified but stripped from comment
and CR LF characters (as far as were present at creation).

=cut

sub body() { shift->{MMF_body} }

#------------------------------------------

=item comment

Returns the comment (part after a semi-colon) in the header-line.

=cut

sub comment() { shift->{MMF_comment} }

#------------------------------------------

=item attribute NAME [, VALUE]

Get the value of an attribute, optionally after setting it to a new value.
Attributes are part of some header lines, and hide themselves in the
comment field.  If the attribute does not exist, then C<undef> is
returned.  For instance

 my $field = Mail::Message::Field->new(
    'Content-Type: text/plain; charset="us-ascii"');
 print $field->attribute('charset');        # --> us-ascii
 print $field->attribute('bitmap') || 'no'  # --> no

=cut

sub attribute($;$)
{   my ($self, $name) = (shift, shift);

    if(@_)
    {   my $value   = shift;
        my $comment = $self->{MMF_comment};
        if(defined $comment)
        {   unless($comment =~ s/\b$name=(['"]?)[^\1]*\1/$name=$1$value$1/)
            {   $comment .= qq(; $name="$value");
            }
        }
        else { $comment = qq($name="$value") }

        $self->{MMF_comment} = $comment;
        return $value;
    }

    my $comment = $self->{MMF_comment} or return;
    $comment =~ m/\b$name=(['"]?)([^\1]*)\1/;
    $2;
}

#------------------------------------------

=item print [FILEHANDLE]

Print the whole header-line to the specified file-handle. One line may
result in more than one printed line, because of the folding of long
lines.  The FILEHANDLE defaults to STDOUT.

=cut

sub print($)
{   my $self = shift;
    my $fh   = shift || \*STDOUT;
    $fh->print($self->toString);
}

#------------------------------------------

=item toString

Returns the whole header-line.

Example:

    my @lines = $field->toString;
    print $field->toString;
    print "$field";

=cut

sub toString()
{   my $self  = shift;

    return wantarray ? @{$self->{MMF_folded}} : join('', @{$self->{MMF_folded}})
        if $self->{MMF_folded};

      defined $self->{MMF_comment}
    ? "$self->{MMF_name}: $self->{MMF_body}; $self->{MMF_comment}\n"
    : "$self->{MMF_name}: $self->{MMF_body}\n";
}

#------------------------------------------

=item toInt

Returns the value which is related to this field as integer.  A check is
performed whether this is right.

=cut

sub toInt()
{   my $self  = shift;
    my $value = $self->{MMF_body};
    return $1 if $value =~ m/^\s*(\d+)\s*$/;

    $self->log(WARNING => "Field content is not a numerical value:\n  "
                           . $self->toString);

    return undef;
}

#------------------------------------------

=item isStructured

(object method or class method)

Examples:

   my $field = Mail::Message::Field->new(From => 'me');
   if($field->isStructured)

   Mail::Message::Field->isStructured('From');

=cut

BEGIN {
%_structured = map { (lc($_) => 1) }
  qw/To Cc Bcc From Date Reply-To Sender
     Resent-Date Resent-From Resent-Sender Resent-To Return-Path
     List-Help List-Post List-Unsubscribe Mailing-List
     Received References Message-ID In-Reply-To
     Content-Length Content-Type
     Delivered-To
     Lines
     MIME-Version
     Precedence
     Status/;
} 

sub isStructured(;$)
{   my $name  = ref $_[0] ? shift->{MMF_name} : $_[1];
    exists $_structured{lc $name};
}

#------------------------------------------

=item nrLines

Returns the number of lines needed to display this header-line.

=cut

sub nrLines()
{   my $self = shift;
    $self->{MMF_folded} ? scalar @{$self->{MMF_folded}} : 1;
}

#------------------------------------------

=item size

Returns the number of bytes needed to display this header-line.

=cut

sub size() {length shift->toString}

#------------------------------------------

=item setWrapLength CHARS

Make the header fold before the specified number of CHARS on a line.  This
will be ignored for un-structured headers.

=cut

sub setWrapLength($)
{   my $self = shift;
    return $self unless $self->isStructured;

    my $wrap = shift;
    delete $self->{MMF_folded};
    my $line = $self->toString;

    return $self if length $line < $wrap;

    my $parser_type = Mail::Box::Parser->defaultParserType;
    $self->{MMF_folded} = [ $parser_type->foldHeaderLine($line, $wrap) ];
    $self;
}

#------------------------------------------

=back

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