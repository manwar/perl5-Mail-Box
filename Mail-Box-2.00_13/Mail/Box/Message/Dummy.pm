
use strict;

package Mail::Box::Message::Dummy;
use base 'Mail::Box::Message';

our $VERSION = '2.00_13';

use Carp;

=head1 NAME

Mail::Box::Message::Dummy - A placeholder for a missing message in a list.

=head1 CLASS HIERARCHY

 Mail::Box::Message::Dummy
 is a Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

=head1 DESCRIPTION

Read C<Mail::Box-Overview> first.

Dummy messages are used by modules which maintain ordered lists of
messages, usually based on message-id.  A good example is
C<Mail::Box::Thread::Manager>, which detects related messages by scanning the
known message headers for references to other messages.  As long as the
referenced messages are not found inside the mailbox, their place is
occupied by a dummy.

Be careful when using modules which may create dummies.  Before trying to
access the header or body use C<isDummy()> to check if the message is a
dummy message.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Message::Dummy> objects:

  MMC body2multipart OPTIONS            MM messageId
  MMC build OPTIONS                     MM modified [BOOL]
  MMC buildFromBody BODY               MBM new OPTIONS
  MBM copyTo FOLDER                     MM nrLines
   MM decoded OPTIONS                   MM parent
  MBM delete                            MM print [FILEHANDLE]
  MBM deleted [BOOL]                   MMC quotePrelude [STRING|FIELD]
   MM encode OPTIONS                   MMC reply OPTIONS
   MR errors                           MMC replySubject STRING
  MBM folder [FOLDER]                   MR report [LEVEL]
   MM get FIELD                         MR reportAll [LEVEL]
   MM guessTimestamp                   MBM seqnr [INTEGER]
   MM isDummy                          MBM setLabel LIST
   MM isMultipart                      MBM shortString
   MM isPart                            MM size
  MBM label STRING [ ,STRING ,...]      MM timestamp
  MBM labels                            MM toplevel
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MM isDelayed
   MM DESTROY                           MR logPriority LEVEL
   MM body [BODY]                       MR logSettings
   MM clone                             MR notImplemented
   MM coerce MESSAGE [,OPTIONS]         MM read PARSER, [BODYTYPE]
  MBM diskDelete                       MBM readBody PARSER, HEAD [, BO...
   MM head [HEAD]                       MM readHead PARSER [,CLASS]
   MR inGlobalDestruction               MM storeBody BODY

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MM = L<Mail::Message>
   MR = L<Mail::Reporter>
  MBM = L<Mail::Box::Message>
  MMC = L<Mail::Message::Construct>

=head1 METHOD

=over 4

#-------------------------------------------

=item new MESSAGE-ID

(Class method) Create a new dummy message to occupy the space for
a real message with the specified MESSAGE-ID.

Examples:

    my $message = Mail::Box::Message::Dummy->new($msgid);
    if($message->isDummy) {...}

=cut

sub new($) { shift->SUPER::new(messageId => shift, deleted => 1) }
 
sub isDummy()    { 1 }

sub shortSize($) {"   0"};

sub shortString()
{   my $self = shift;
    sprintf "----(%2d) <not found>";
}

sub body()
{    shift->log(INTERNAL => "You cannot take the body of a dummy");
     ();
}

sub head()
{    shift->log(INTERNAL => "You cannot take the head of a dummy");
     ();
}

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