
use strict;

package Mail::Message;

use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;

use Mail::Address;
use Carp;
use Scalar::Util 'blessed';
use IO::Lines;

=chapter NAME

Mail::Message::Construct::Build - building a Mail::Message from components

=chapter SYNOPSIS

 my $msg3 = Mail::Message->build
   (From => 'me', data => "only two\nlines\n");

 my $msg4 = Mail::Message->buildFromBody($body);

=chapter DESCRIPTION

Complex functionality on M<Mail::Message> objects is implemented in
different files which are autoloaded.  This file implements the
functionality related to building of messages from various components.

=chapter METHODS

=section Constructing a message

=c_method build [MESSAGE|BODY], CONTENT

Simplified message object builder.  In case a MESSAGE is
specified, a new message is created with the same body to start with, but
new headers.  A BODY may be specified as well.  However, there are more
ways to add data simply.

The CONTENT is a list of key-value pairs and header field objects.
The keys which start with a capital are used as header-lines.  Lowercased
fields are used for other purposes as listed below.  Each field may be used
more than once.  If more than one C<data>, C<file>, and C<attach> is
specified, a multi-parted message is created.

This C<build> method will use M<buildFromBody()> when the body object has
been constructed.  Together, they produce your message.

=option  data STRING|ARRAY-OF-LINES
=default data undef

The text for one part, specified as one STRING, or an ARRAY of lines.  Each
line, including the last, must be terminated by a newline.  This argument
is passed to M<Mail::Message::Body::new(data)> to
construct one.

  data => [ "line 1\n", "line 2\n" ]     # array of lines
  data => <<'TEXT'                       # string
 line 1
 line 2
 TEXT

=option  file FILENAME|FILEHANDLE|IOHANDLE
=default file undef

Create a body where the data is read from the specified FILENAME,
FILEHANDLE, or object of type M<IO::Handle>.  Also this body is used
to create a M<Mail::Message::Body>.

 my $in = IO::File->new('/etc/passwd', 'r');

 file => 'picture.jpg'                   # filename
 file => \*MYINPUTFILE                   # file handle
 file => $in                             # IO::Handle

=option  files ARRAY-OF-FILE
=default files C<[ ]>

See option file, but then an array reference collection more of them.

=option  attach BODY|MESSAGE|ARRAY-OF-BODY
=default attach undef

One attachment to the message.  Each attachment can be full MESSAGE or a BODY.

 attach => $folder->message(3)->decoded  # body
 attach => $folder->message(3)           # message

=option  head HEAD
=default head undef

Start with a prepared header, otherwise one is created.

=examples

 my $msg = Mail::Message->build
  ( From   => 'me@home.nl'
  , To     => Mail::Address->new('your name', 'you@yourplace.aq')
  , Cc     => 'everyone@example.com'
  , $other_message->get('Bcc')

  , data   => [ "This is\n", "the first part of\n", "the message\n" ]
  , file   => 'myself.gif'
  , file   => 'you.jpg'
  , attach => $signature
  );

=cut

sub build(@)
{   my $class = shift;

    my @parts
      = ! ref $_[0] ? ()
      : $_[0]->isa('Mail::Message')       ? shift
      : $_[0]->isa('Mail::Message::Body') ? shift
      :               ();

    my ($head, @headerlines);
    while(@_)
    {   my $key = shift;
        if(ref $key && $key->isa('Mail::Message::Field'))
        {   push @headerlines, $key;
            next;
        }

        my $value = shift;
        if($key eq 'head')
        {   $head = $value }
        elsif($key eq 'data')
        {   push @parts, Mail::Message::Body->new(data => $value) }
        elsif($key eq 'file')
        {   push @parts, Mail::Message::Body->new(file => $value) }
        elsif($key eq 'files')
        {   push @parts, map {Mail::Message::Body->new(file => $_) } @$value }
        elsif($key eq 'attach')
        {   push @parts, ref $value eq 'ARRAY' ? @$value : $value }
        elsif($key =~ m/^[A-Z]/)
        {   push @headerlines, $key, $value }
        else
        {   croak "Skipped unknown key $key in build." } 
    }

    my $body
       = @parts==0 ? Mail::Message::Body::Lines->new()
       : @parts==1 ? $parts[0]
       : Mail::Message::Body::Multipart->new(parts => \@parts);

    $class->buildFromBody($body, $head, @headerlines);
}

#------------------------------------------

=c_method buildFromBody BODY, [HEAD], HEADERS

Shape a message around a BODY.  Bodies have information about their
content in them, which is used to construct a header for the message.
You may specify a HEAD object which is pre-initialized, or one is
created for you (also when HEAD is C<undef>).
Next to that, more HEADERS can be specified which are stored in that
header.

Header fields are added in order, and before the header lines as
defined by the body are taken.  They may be supplied as key-value
pairs or M<Mail::Message::Field> objects.  In case of a key-value
pair, the field's name is to be used as key and the value is a
string, address (M<Mail::Address> object), or array of addresses.

A C<Date>, C<Message-Id>, and C<MIME-Version> field are added unless
supplied.

=examples

 my $type = Mail::Message::Field->new('Content-Type', 'text/html'
   , 'charset="us-ascii"');

 my @to   = ( Mail::Address->new('Your name', 'you@example.com')
            , 'world@example.info'
            );

 my $msg  = Mail::Message->buildFromBody
   ( $body
   , From => 'me@example.nl'
   , To   => \@to
   , $type
   );

=cut

sub buildFromBody(@)
{   my ($class, $body) = (shift, shift);
    my @log     = $body->logSettings;

    my $head;
    if(ref $_[0] && $_[0]->isa('Mail::Message::Head')) { $head = shift }
    else
    {   shift unless defined $_[0];   # undef as head
        $head = Mail::Message::Head::Complete->new(@log);
    }

    while(@_)
    {   if(ref $_[0]) {$head->add(shift)}
        else          {$head->add(shift, shift)}
    }

    my $message = $class->new
     ( head => $head
     , @log
     );

    $message->body($body);

    # be sure the message-id is actually stored in the header.
    $head->add('Message-Id' => '<'.$message->messageId.'>')
        unless defined $head->get('message-id');

    $head->add(Date => Mail::Message::Field->toDate)
        unless defined $head->get('Date');

    $head->add('MIME-Version' => '1.0')  # required by rfc2045
        unless defined $head->get('MIME-Version');

    $message;
}

1;