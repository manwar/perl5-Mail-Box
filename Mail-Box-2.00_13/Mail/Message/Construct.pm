
use strict;

# file Mail::Message::Construct extends functionalities from Mail::Message

package Mail::Message;

our $VERSION = '2.00_13';

use Mail::Address;
use Carp;

=head1 NAME

 Mail::Message::Construct - Extends the functionality of a Mail::Message

=head1 SYNOPSIS

 my Mail::Message $message = $folder->message(4);
 my Mail::Message $reply   = $message->reply;
 $message->body2multipart;

=head1 DESCRIPTION

Read C<Mail::Box-Overview> and C<Mail::Message> first.

When complex methods are called on a C<Mail::Message>-object, this
package is autoloaded to supply that functionality.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Construct> objects:

      body2multipart OPTIONS               quotePrelude [STRING|FIELD]
      build OPTIONS                        reply OPTIONS
      buildFromBody BODY                   replySubject STRING

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item reply OPTIONS

Start a reply to this message.  Some of the header-lines of the original
message will be taken.  A message-id will be assigned.  Some header lines
will be updated to facilitate message-thread detection
(see C<Mail::Box::Thread::Manager>).

In case you C<reply> on a multipart message, it will answer on the first
message-part.  You may also reply explicitly on a single message-part.

 OPTIONS         DESCRIBED IN              DEFAULT
 body            Mail::Message::Construct  undef
 body_type       Mail::Message::Construct  <class of current body>
 cc              Mail::Message::Construct  <'cc' in current>
 from            Mail::Message::Construct  <'to' in current>
 group_reply     Mail::Message::Construct  1
 head            Mail::Message::Construct  <new Mail::Message::Head>
 include         Mail::Message::Construct  'INLINE'
 message_id      Mail::Message::Construct  <uniquely generated>
 message_type    Mail::Message::Construct  'Mail::Message'
 postlude        Mail::Message::Construct  undef
 prelude         Mail::Message::Construct  undef
 quote           Mail::Message::Construct  '=E<gt> '
 strip_signature Mail::Message::Construct  qr/^--\s/
 subject         Mail::Message::Construct  <see replySubject>
 to              Mail::Message::Construct  <'from' in current>

The OPTIONS are:

=over 4

=item * body =E<gt> BODY

Specifies the body of the message which is the reply.  Not used when
C<include> is C<'INLINE'>.  Adviced in other cases: prepare the body
of the reply before the reply is called.  It will avoid needless
copying within C<Mail::Message>.

=item * body_type =E<gt> CLASS

Specifies the type of the body to be created.  If the reply will be
a multipart message (C<include> equals C<'ATTACH'>), this must be
a sub-class of C<Mail::Message::Body::Multipart>.  Otherwise any
sub-class of C<Mail::Message::Body> will satisfy.

If nothing is specified, the body type of the produced will be the same
as that of the original (except when a multipart is to be created).

=item * group_reply =E<gt> BOOLEAN

Will the C<CC> headers be copied too?

=item * include =E<gt> 'NO'|'INLINE'|'ATTACH'

Must the message where this is a reply to be included in the message?
If 'NO' then note, with 'INLINE' a reply body is composed. 'ATTACH'
will create a multipart body, where the original message is added
after the specified body.

=item * message_id =E<gt> STRING

Supply a STRING as specific message-id for the reply.  By default, one is
generated for you.  If there are no angles around your id, they will be
added.

=item * message_type =E<gt> CLASS

Create a message with the requested type.  By default, it will be a
C<Mail::Message>.  This is correct, because it will be coerced into
the correct folder message type when it is added to that folder.

=item * max_signature =E<gt> INTEGER

Passed to C<stripSignature> on the body as parameter C<max_lines>.  Only
effective for single-part messages.

=item * prelude =E<gt> BODY

The line(s) which will be added before the quoted reply lines.  If nothing
is specified, the result of the C<quotePrelude()> method (as described below)
is taken.  When C<undef> is specified, no prelude will be added.  Create
a BODY for the lines first.

=item * postlude =E<gt> BODY

The line(s) which to be added after the quoted reply lines.  Create a
body for it first.

=item * quote =E<gt> CODE|STRING

Mangle the lines of an C<INLINE>d reply with CODE, or by prepending a
STRING to each line.  The routine specified by CODE is called when the
line is in C<$_>.

By default, C<'E<gt> '> is added before each line.  Specify C<undef> to
disable quoting.  This option is processed after the body has been decoded.

=item * strip_signature =E<gt> REGEXP|STRING|CODE

Is passed to the body's C<stripSignature> method (see C<Mail::Message::Body>)
as C<pattern> unless the source text is not included.  The signature is
stripped before quoting.

When a multipart body is encountered, the parts which look like signatures
will be removed.  In this case, the value of this option does not matter,
as long as it is present.  See C<Mail::Message::Body::Multipart>.

=item * subject =E<gt> STRING|CODE

Force the subject line to the specific STRING, or the result of the
subroutine specified by CODE.  The subroutine will be called passing
the subject of the original message as only argument.  By default,
the C<replySubject> method (described below) is used.

=back

You may wish to overrule some of the default settings for the
reply immediately (or you may do later with C<set()> on the header).
To overrule use

=over 4

=item * to =E<gt> STRING

The destination of your message, by default taken from the C<From> field
of the source message.

=item * from =E<gt> STRING

Your identification, by default taken from the C<To> field of the
source message.

=item * cc =E<gt> STRING

The carbon-copy receivers, by default a copy of the C<Cc> field of
the source message.

=back

=cut

# tests in t/35reply2m.t

sub reply(@)
{   my ($self, %args) = @_;

    my $include  = $args{include}   || 'INLINE';
    my $source   = $self->body;

    return $source->part(0)->reply(%args)
        if $include eq 'INLINE' && $self->isMultipart;

    $include     = 'ATTACH'
        if $include ne 'NONE' && ($source->isBinary || $source->isMultipart);

    my $bodytype = $args{body_type} || ref $source;

    #
    # Create the body
    #

    my $strip = !exists $args{strip_signature}
             || defined $args{strip_signature};

    my $stripped
      = $include ne 'INLINE' ? undef
      : !$strip              ? $self->decoded
      : $self->decoded(result_type => $bodytype)
           ->stripSignature
         ( pattern     => $args{strip_signature}
         , max_lines   => $args{max_signature}
         , result_type => $bodytype
         );

    my $body;
    if($include eq 'NONE')
    {   $body = defined $args{body} ? $args{body} : $bodytype->new(data => []);
    }
    elsif($include eq 'INLINE')
    {   my $quote
          = defined $args{quote} ? $args{quote}
          : exists $args{quote}  ? undef
          :                        '> ';

        $body = $stripped;
        if(defined $quote)
        {   my $quoting = ref $quote ? $quote : sub {$quote . $_};
            $body = $stripped->foreachLine($quoting);
        }
    }
    elsif($include eq 'ATTACH')
    {   $self->notImplemented;
    }
    else
    {   $self->log(ERROR => "Cannot include source as $include.");
        return;
    }

    #
    # Collect header info
    #

    my $mainhead = $self->toplevel->head;

    # Where it comes from
    my $from;
    unless($from = $args{from})
    {   $from = $mainhead->get('To');  # Me, with the alias known by the user.
        $from = $from->body if $from;
    }

    # To whom to send
    my $to;
    unless($to = $args{to})
    {   $to = $mainhead->get('reply-to') || $mainhead->get('from')
              || $mainhead->get('sender');
        $to = $to->body if $to;
    }
    return undef unless $to;

    # Add CC
    my $cc;
    if(!($cc = $args{cc}) && $args{group_reply})
    {   $cc = $mainhead->get('cc');
        $cc = $cc->body if $cc;
    }

    # Create a subject
    my $subject;
    if(exists $args{subject} && ! ref $args{subject})
    {   $subject       = $args{subject}; }
    else
    {   my $rawsubject = $mainhead->get('subject')->body || 'your mail';
        my $make       = $args{subject} || \&replySubject;
        $subject       = $make->($rawsubject);
    }

    # Create a nice message-id
    my $msgid   = $args{message_id};
    $msgid      = "<$msgid>" if $msgid && $msgid !~ /^\s*\<.*\>\s*$/;

    # Thread information
    my $origid  = '<'.$self->messageId.'>';
    my $refs    = $mainhead->get('references');

    # Prelude
    my $prelude
      = defined $args{prelude} ? $args{prelude}
      : exists $args{prelude}  ? undef
      : $bodytype->new(data => [ $self->quotePrelude($to) ]);
 
    #
    # Create the message.
    #

    my $total   = $body->concatenate($prelude, $body, $args{postlude});
    my $msgtype = $args{message_type} || 'Mail::Message';
    my $reply   = $msgtype->buildFromBody($total);
    my $newhead = $reply->head;

    $newhead->set(From => $from || '(undisclosed)');
    $newhead->set(To => $to);
    $newhead->set(Cc => $cc) if $cc;
    $newhead->set('Message-Id' => $msgid || $newhead->createMessageId);
    $newhead->set('In-Reply-To' => $origid);
    $newhead->set(References    => ($refs ? "$origid $refs" : $origid));
    $newhead->set(Subject => $subject);

    # Ready

    $self->log(PROGRESS => 'Reply created from '.$origid);
    $reply;
}

#------------------------------------------

=item replySubject STRING

Create a subject for a message which is a reply for this one.  This routine
tries to count the level of reply in subject field, and transform it into
a standard form.  Please contribute improvements.

  subject                 --> Re: subject
  Re: subject             --> Re[2]: subject
  Re[X]: subject          --> Re[X+1]: subject
  subject (Re)            --> Re[2]: subject
  subject (Forw)          --> Re[2]: subject
                          --> Re: your mail

=cut

# tests in t/35reply1rs.t

sub replySubject($)
{   my $subject  = shift;
    my @subject  = split /\:/, $subject;
    my $re_count = 1;

    # Strip multiple Re's from the start.

    while(@subject)
    {   last if $subject[0] =~ /[A-QS-Za-qs-z][A-DF-Za-df-z]/;

        for(shift @subject)
        {   while( /\bRe(?:\[\s*(\d+)\s*\]|\b)/g )
            {   $re_count += defined $1 ? $1 : 1;
            }
        }
    }

    # String multiple Re's from the end.

    if(@subject)
    {   for($subject[-1])
        {   $re_count++ while s/\s*\(\s*(re|forw)\W*\)\s*$//i;
        }
    }

    # Create the new subject string.

    my $text = (join ':', @subject) || 'your mail';
    for($text)
    {  s/^\s+//;
       s/\s+$//;
    }

    $re_count==1 ? "Re: $text" : "Re[$re_count]: $text";
}

#------------------------------------------

=item quotePrelude [STRING|FIELD]

Produces a list of lines (usually only one), which will preceed the
quoted body of the message.  STRING must comply to the RFC822 email
address specification, and is usually the content of a C<To> or C<From>
header line.  If a FIELD is specified, the field's body must be
compliant.  Without argument -or when the argument is C<undef>- a
slightly different line is produced.

An characteristic example of the output is

  at Thu Oct 13 04:54:34 1995, him@example.com wrote:

=cut

sub quotePrelude($)
{   my ($self, $user) = @_;
 
    $user = $user->body
       if ref $user && $user->isa('Mail::Message::Field');

    my @addresses = $user ? Mail::Address->parse($user) : ();
    my $address   = $addresses[0];
    my $from      = $address ? $address->name : 'an unknown person';

    my $time    = gmtime $self->timestamp;
    "at $time, $from wrote:\n";
}

#------------------------------------------

=item body2multipart OPTIONS

Create a multipart from a single-part message.  This is needed on the
moment an attachment is added to a single-part body.  If the body
already is a multipart, a nested multipart will be the result.

The OPTIONS are passed to the creation of the multipart-body-object.
See C<Mail::Message::Body::Multipart::new>

=cut

sub body2multipart(@)
{   my $self = shift;

    $self->log(PROGRESS => 'Transformed body to multipart');

    my $multi = Mail::Message::Body::Multipart->new
      ( @_
      , message  => $self
      ) or return;

    my $part = $self->body;
    $part->message($multi);

    $multi->addPart($part);

    $self->body($multi);
    $self;
}

#------------------------------------------

=item build OPTIONS

(Class method)
Simplified message-object builder.  The OPTIONS are a list of
field-name and related values pairs, representing header lines.  The
name C<data> is the only exception, and refers to a list of lines which
has to be stored in the body.  All other names start with an uppercase,
as commonly used in MIME headers.  Names may appear more than once.

Example:

 my $msg = Mail::Message->build(From => 'me@home.nl',
   To => 'you@yourplace.aq', CC => 'everyone@example.com',
   data => [ 'This is', 'the body of', 'the message' ] );

=cut

sub build(@)
{   my $class = shift;

    require Mail::Message::Head::Complete;
    require Mail::Message::Body::Lines;

    my $head  = Mail::Message::Head::Complete->new;
    my $body;

    while(@_)
    {   my ($key, $value) = (shift, shift);
        if($key eq 'data')
        {      $body = Mail::Message::Body::Lines->new(data => $value) }
        else { $head->add($key => $value) }
    }

    $class->new(head => $head, body => $body);
}

#------------------------------------------

=item buildFromBody BODY

(Class method)
Shape a message around a BODY.  Bodies have information about their
content in them, which is used to construct a header for the message.

=cut

sub buildFromBody($)
{   my ($class, $body) = @_;
    my @log     = $body->logSettings;

    my $head    = Mail::Message::Head::Complete->new(@log);
    my $message = Mail::Message->new
     ( head => $head
     , @log
     );

    $message->body($body);
    $message;
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