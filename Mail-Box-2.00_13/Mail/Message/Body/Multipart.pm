use strict;
use warnings;

package Mail::Message::Body::Multipart;
use base 'Mail::Message::Body';

use Mail::Message::Body::Lines;
use Mail::Message::Part;

our $VERSION = '2.00_13';

use Carp;

=head1 NAME

 Mail::Message::Body::Multipart - Body of a Mail::Message with attachments

=head1 CLASS HIERARCHY

 Mail::Message::Body::Multipart
 is a Mail::Message::Body + ::Construct + ::Encode
 is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Message::Body, plus

 if($body->isMultipart) {
    my @attachments = $body->parts;
    my $attachment3 = $body->part(2);
    my $before      = $body->preamble;
    my $after       = $body->epiloque;
    my $removed     = $body->removePart(1);
 }

=head1 DESCRIPTION

READ C<Mail::Message::Body> FIRST. This manual-page only describes the
extentions to the default body functionality.

The body (content) of a message can be stored in various ways.  In this
manual-page you find the description of extra functionality you have
when a message contains attachments (parts).

=head1 METHOD INDEX

The general methods for C<Mail::Message::Body::Multipart> objects:

 MMBC attach MESSAGES                  MMB modified [BOOL]
      boundary [STRING]                    new OPTIONS
  MMB checked [BOOLEAN]                MMB nrLines
 MMBC concatenate BODY [,BODY, .....       part INDEX
  MMB decoded OPTIONS                      parts
  MMB disposition [STRING|FIELD]           preamble
      encode OPTIONS                   MMB print [FILE]
      epilogue                         MMB reply OPTIONS
   MR errors                            MR report [LEVEL]
  MMB file                              MR reportAll [LEVEL]
 MMBC foreachLine CODE                 MMB size
  MMB isBinary                         MMB string
  MMB isDelayed                       MMBC stripSignature OPTIONS
  MMB isMultipart                       MR trace [LEVEL]
  MMB lines                            MMB transferEncoding
   MR log [LEVEL [,STRINGS]]           MMB type
  MMB message [MESSAGE]                 MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                         MMB load
   MR DESTROY                           MR logPriority LEVEL
 MMBE addTransferEncHandler NAME,...    MR logSettings
  MMB clone                             MR notImplemented
 MMBE getTransferEncHandler TYPE       MMB read PARSER, HEAD, BODYTYPE...
   MR inGlobalDestruction              MMB start

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMB = L<Mail::Message::Body>
 MMBC = L<Mail::Message::Body::Construct>
 MMBE = L<Mail::Message::Body::Encode>

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION    DESCRIBED IN                    DEFAULT
 based_on    Mail::Message::Body            undef
 boundary    Mail::Message::Body::Multipart undef
 charset     Mail::Message::Body            'us-ascii'
 data        Mail::Message::Body            undef
 disposition Mail::Message::Body            undef
 epilogue    Mail::Message::Body::Multipart undef
 log         Mail::Reporter                 'WARNINGS'
 message     Mail::Message::Body            undef
 mime_type   Mail::Message::Body            'multipart/mixed'
 modified    Mail::Message::Body            0
 preamble    Mail::Message::Body::Multipart undef
 parts       Mail::Message::Body::Multipart undef
 trace       Mail::Reporter                 'WARNINGS'
 transfer_encoding Mail::Message::Body      'NONE'


=over 4

=item * parts => ARRAY

Specifies an initial list of parts in this body.

=back

=cut

#------------------------------------------

sub init($)
{   my ($self, $args) = @_;
    my $based = $args->{based_on};
    $args->{mime_type} ||= 'multipart/mixed' unless defined $based;

    $self->SUPER::init($args);

    if(defined $based)
    {   $self->boundary($args->{boundary} || $based->boundary);
        $self->{MMBM_preamble} = $args->{preamble} || $based->preamble;
        $self->{MMBM_parts}    = $args->{parts}    || [$based->parts];
        $self->{MMBM_epilogue} = $args->{epilogue} || $based->epilogue;
    }
    else
    {   $self->boundary($args->{boundary} ||$self->type->attribute('boundary'));
        $self->{MMBM_preamble} = $args->{preamble};
        $self->{MMBM_parts}    = $args->{parts} || [];
        $self->{MMBM_epilogue} = $args->{epilogue};
    }

    $self;
}

#------------------------------------------

sub isMultipart() {1}

#------------------------------------------

=item encode OPTIONS

Encode the body.  An encode on a multipart body is recursive into each
part.  New bodies will be created if any of the parts is encoded.

 OPTION            DESCRIBED IN         DEFAULT
 charset           Mail::Message::Body  undef
 mime_type         Mail::Message::Body  undef
 result_type       Mail::Message::Body  <same as source>
 transfer_encoding Mail::Message::Body  undef

=cut

sub encode(@)
{   my ($self, %args) = @_;

    my $changes  = 0;

    my $encoded_preamble;
    if(my $preamble = $self->preamble)
    {   $encoded_preamble = $preamble->encode(%args);
        $changes++ unless $preamble == $encoded_preamble;
    }

    my $encoded_epilogue;
    if(my $epilogue = $self->epilogue)
    {   $encoded_epilogue = $epilogue->encode(%args);
        $changes++ unless $epilogue == $encoded_epilogue;
    }

    my @encoded_bodies;
    foreach my $part ($self->parts)
    {   my $part_body    = $part->body;
        my $encoded_body = $part_body->encode(%args);

        $changes++ if $encoded_body != $part_body;
        push @encoded_bodies, [$part, $encoded_body];
    }

    return $self unless $changes;

    my @encoded_parts;
    foreach my $encoded (@encoded_bodies)
    {   my ($part, $body) = @$_;
        my $encoded_part  = ref($part)->new(head => $part->head->clone);
        $encoded_part->body($body);
        push @encoded_parts, $encoded_part;
    }

    my $type = $args{result_type} || ref $self;

    $type->new
      ( preamble => $encoded_preamble
      , parts    => \@encoded_parts
      , epilogue => $encoded_epilogue
      , boundary => $self->boundary
      , based_on => $encoded_preamble
      , $self->logSettings
      );
}

#------------------------------------------

sub string() { join '', shift->lines }

#------------------------------------------

sub lines()
{   my $self     = shift;

    my $boundary = $self->boundary;
    my @lines;

    my $preamble = $self->preamble;
    push @lines, $preamble->lines if $preamble;

    foreach ($self->parts)
    {   push @lines, "--$boundary\n", $_->body->lines;
    }

    push @lines, "\n--$boundary--\n";

    my $epilogue = $self->epilogue;
    push @lines, $epilogue->lines if $epilogue;

    wantarray ? @lines : \@lines;
}

#------------------------------------------

sub file() {shift->notImplemented}

#------------------------------------------

sub nrLines()
{   my $self   = shift;
    my $nr     = 1;

    if(my $preamble = $self->preamble) { $nr += $preamble->nrLines }
    $nr       += 2 + $_->nrLines foreach $self->parts;
    if(my $epilogue = $self->epilogue) { $nr += $epilogue->nrLines }

    $nr;
}

#------------------------------------------

sub size()
{   my $self   = shift;
    my $bbytes = length($self->boundary) +3;

    my $bytes  = 0;
    if(my $preamble = $self->preamble) { $bytes += $preamble->size }
    $bytes    += $bbytes + 2;  # last boundary
    $bytes    += $bbytes + 1 + $_->size foreach $self->parts;
    if(my $epilogue = $self->epilogue) { $bytes += $epilogue->size }

    $bytes;
}

#------------------------------------------

sub print(;$)
{   my $self = shift;
    my $out  = shift || \*STDOUT;

    my $boundary = $self->boundary;
    if(my $preamble = $self->preamble)
    {   $preamble->print($out);
    }

    my @parts    = $self->parts;
    while(@parts)
    {   $out->print("--$boundary\n");
        shift(@parts)->print($out);
        $out->print("\n");
    }

    $out->print("--$boundary--\n");

    if(my $epilogue = $self->epilogue)
    {   $epilogue->print($out);
    }

    $self;
}

#------------------------------------------

=item preamble

Returns the preamble (the text before the first message part --attachment),
The preamble is stored in a BODY object, and its encoding is derived
from the multipart header.

=cut

sub preamble() {shift->{MMBM_preamble}}

#------------------------------------------

=item epilogue

Returns the epilogue (the text after the last message part --attachment),
The preamble is stored in a BODY object, and its encoding is derived
from the multipart header.

=cut

sub epilogue() {shift->{MMBM_epilogue}}

#------------------------------------------

=item parts

In LIST context, the current list of parts (attachments) is returned,
In SCALAR context the length of the list is returned, so the number
of parts for this multiparted body.  This is normal behavior of Perl.

Examples:

 print "Number of attachments: ", scalar $message->body->parts;

 foreach my $part ($message->body->parts) {
     print "Type: ", $part->get('Content-Type');
 }

=cut

sub parts(@) { @{shift->{MMBM_parts}} }

#-------------------------------------------

=item part INDEX

Returns only the part with the specified INDEX.  You may use a negative
value here, which counts from the back in the list.

Example:

 $message->body->part(2)->print;

=cut

sub part($) { shift->{MMBM_parts}[shift] }

#-------------------------------------------

=item boundary [STRING]

Returns the boundary which is used to separate the parts in this
body.  If none was read from file, then one will be assigned.  With
STRING you explicitly set the boundary to be used.

=cut

my $unique_boundary = time;

sub boundary(;$)
{   my $self      = shift;
    my $mime      = $self->type;
    my $boundary  = $mime->attribute('boundary');

    if(@_ || !defined $boundary)
    {   $boundary = shift || "boundary-" . $unique_boundary++;
        $self->type->attribute(boundary => $boundary);
    }

    $boundary;
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

sub read($$)
{   my ($self, $parser, $head, $bodytype) = @_;

    my $boundary = $self->boundary;

    $parser->pushSeparator("--$boundary");
    my @msgopts  =
     ( $self->logSettings
     , head_wrap => $head->wrapLength
     );

    my @sloppyopts = 
      ( mime_type         => 'text/plain'
      , transfer_encoding => ($head->get('Content-Transfer-Encoding') || undef)
      );

    # Get preamble.
    my $headtype = ref $head;

    my $preamble = Mail::Message::Body::Lines->new(@msgopts, @sloppyopts)
       ->read($parser, $head);

    $self->{MMBM_preamble} = $preamble if $preamble->size;

    # Get the parts.

    while(my $sep = $parser->readSeparator)
    {   last if $sep eq "--$boundary--\n";

        my $part = Mail::Message::Part->new
         ( @msgopts
         , parent => $self
         );

        last unless $part->read($parser, $bodytype);
        push @{$self->{MMBM_parts}}, $part;
    }

    # Get epilogue

    $parser->popSeparator;
    my $epilogue = Mail::Message::Body::Lines->new(@msgopts, @sloppyopts)
      ->read($parser, $head);

    $self->{MMBM_epilogue} = $epilogue if $epilogue->size;

    $self;
}

#------------------------------------------

sub clone()
{   my $self     = shift;
    my $preamble = $self->preamble;
    my $epilogue = $self->epilogue;

    ref($self)->new
     ( $self->logSettings
     , based_on => $self
     , preamble => ($preamble ? $preamble->clone : undef)
     , epilogue => ($epilogue ? $epilogue->clone : undef)
     , parts    => [ map {$_->clone} $self->parts ]
     );
}

#-------------------------------------------

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