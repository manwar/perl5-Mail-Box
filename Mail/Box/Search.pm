
package Mail::Box::Search;
use base 'Mail::Reporter';

use strict;
use warnings;

use Carp;

=head1 NAME

Mail::Box::Search - select messages within a mail box

=head1 SYNOPSIS

 use Mail::Box::Manager;
 my $mgr    = Mail::Box::Manager->new;
 my $folder = $mgr->open('Inbox');

 my $filter = Mail::Box::Search::Grep->new;
 my @msgs   = $filter->search($folder, ...);
 if($filter->search($message)) {...}

=head1 DESCRIPTION

This Mail::Box::Search class is the base class for various message scan
algorithms.  The selected messages can be labeled.  Boolean operations on
messages are supported.

Currently implemented searches:

=over 4

=item Mail::Box::Search::Grep

Match header or body against a regular expression in a UNIX C<grep> like
fashion.

=back

A Mail::Box::Search::Spam is high on the wishlist.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

Create a filter.

=option  binaries BOOLEAN
=default binaries <false>

Whether to include binary bodies in the search.

=option  decode BOOLEAN
=default decode <true>

Decode the messages before the search takes place.  Even plain text messages
can be encoded, for instance as C<quoted-printable>, which may disturb the
results.  However, decoding will slow-down the search.

=option  details undef|'PRINT'|'DELETE'|REF-ARRAY|CODE
=default details undef

The exact functionality of this parameter differs per search method, so
read the applicable man-page.  In any case C<undef> means that details
are not collected for this search, which is the fastest search.

C<PRINT> will cause a call to a standard printing routine per line
found.  C<DELETE> will flag the message to be flagged for deletion.
You may also specify your own CODE reference.  With an reference
to an array, the information about the matches is collected as a list
of hashes, one hash per match.

=option  in 'HEAD'|'BODY'|'MESSAGE'
=default in 'BODY;

Where to look for the match.

=option  delayed BOOLEAN
=default delayed <true>

Include the delayed messages (which will be parsed) in the search.  If you
set this to false, you may find fewer hits.

=option  deleted BOOLEAN
=default deleted <false>

In most cases, you will not be interested in results which are
found in messages flagged to be deleted.  However, with this option
you can specify you want them to be searched too.

=option  label STRING
=default label undef

Mark all selected messages with the specified STRING.  If this field is
not specified, the message will not get a label; search() also returns
a list of selected messages.

=option  limit NUMBER
=default limit 0

Limit the search to the specified NUMBER of messages.  When the NUMBER
is positive, the search starts at the first message in the folder or
thread.  A negative NUMBER starts at the end of the folder.  If the limit
is set to zero, there is no limit.

=option  logical 'REPLACE'|'AND'|'OR'|'NOT'|'AND NOT'|'OR NOT'
=default logical 'REPLACE'

Only applicable in combination with a C<label>.
How to handle the existing labels.  In case of C<REPLACE>, messages
which already are carrying the label are stripped from their
selection (unless they match again).  With C<AND>, the message must
be selected by this search and already carry the label, otherwise the
label will not be set.  Specify C<OR> to have newly selected messages
added to the set of already selected messages.

C<NOT> is true for messages which do not fulfill the search.  The
details output will still contain the places where the the match was
found, however those messages will complementary set of messages will
be labeled and returned.

=option  multiparts BOOLEAN
=default multiparts <true>

Are multiparts to be included in the search results?  Some MUA have
problems handling details received from the search.  When this flag
is turned off, the body of multiparts will be ignored.  The parts
search will include the preamble and epilogue.

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my $in = $args->{in} || 'BODY';
    @$self{ qw/MBS_check_head MBS_check_body/ }
      = $in eq 'BODY'    ? (0,1)
      : $in eq 'HEAD'    ? (1,0)
      : $in eq 'MESSAGE' ? (1,1)
      : croak "Search in BODY, HEAD or MESSAGE not $in.";

    croak "Cannot search in header."
        if $self->{MBS_check_head} && !$self->can('inHead');

    croak "Cannot search in body."
        if $self->{MBS_check_body} && !$self->can('inBody');

    my $logic               = $args->{logical}  || 'REPLACE';
    $self->{MBS_negative}   = $logic =~ s/\s*NOT\s*$//;
    $self->{MBS_logical}    = $logic;

    $self->{MBS_label}      = $args->{label};
    $self->{MBS_binaries}   = $args->{binaries} || 0;
    $self->{MBS_limit}      = $args->{limit}    || 0;
    $self->{MBS_decode}     = $args->{decode}   || 1;
    $self->{MBS_no_deleted} = not $args->{deleted};
    $self->{MBS_delayed}    = defined $args->{delayed} ? $args->{delayed} : 1;
    $self->{MBS_multiparts}
       = defined $args->{multiparts} ? $args->{multiparts} : 1;

    $self;
}

#-------------------------------------------

=head2 Searching

=cut

#-------------------------------------------

=method search FOLDER|THREAD|MESSAGE|ARRAY-OF-MESSAGES

Check which messages from the FOLDER (Mail::Box) match the
search parameters.  The matched messages are returned as list.  You
can also specify a THREAD (Mail::Box::Thread::Node), one single
MESSAGE (Mail::Message), or an array of messages.

Sometimes we know how only one match is needed.  In this case, this
searching will stop at the first match.  For instance, when C<limit> is C<-1>
or C<1>, or when the search in done in scalar context.

=examples

 my $grep = Mail::Box::Search::Grep->new
  ( match   => 'My Name Is Nobody'
  , details => 'PRINT'
  );

 $grep->search($folder);

 my $message = $folder->message(3);
 $grep->search($message);

 my $thread  = $message->threadStart;
 $grep->search($thread);

=cut

sub search(@)
{   my ($self, $object) = @_;

    my $label         = $self->{MBS_label};
    my $limit         = $self->{MBS_limit};

    my @messages
      = ref $object eq 'ARRAY'        ? @$object
      : $object->isa('Mail::Box')     ? $object->messages
      : $object->isa('Mail::Message') ? ($object)
      : $object->isa('Mail::Box::Thread::Node') ? $object->threadMessages
      : croak "Expect messages to search, not $object.";

    my $take = 0;
    if($limit < 0)    { $take = -$limit; @messages = reverse @messages }
    elsif($limit > 0) { $take = $limit }
    elsif(!defined $label && !wantarray && !$self->{MBS_details}) {$take = 1 }

    my $logic         = $self->{MBS_logical};
    my @selected;
    my $count = 0;

    foreach my $message (@messages)
    {   next if $self->{MBS_no_deleted} && $message->deleted;
        next unless $self->{MBS_delayed} || !$message->isDelayed;

        my $set = defined $label ? $message->label($label) : 0;

        my $selected
          =  $set && $logic eq 'OR'  ? 1
          : !$set && $logic eq 'AND' ? 0
          : $self->{MBS_negative}    ? ! $self->searchPart($message)
          :                            $self->searchPart($message);

        $message->label($label => $selected) if defined $label;
        if($selected)
        {   push @selected, $message;
            $count++;
            last if $take && $count == $take;
        }
    }

    $limit < 0 ? reverse @selected : @selected;
}


#-------------------------------------------

=method searchPart PART

Search this message PART for matches.

=cut

sub searchPart($)
{  my ($self, $part) = @_;

   my $matched = 0;
   $matched  = $self->inHead($part, $part->head)
      if $self->{MBS_check_head};

   return $matched unless $self->{MBS_check_body};
   return $matched if $matched && !$self->{MBS_details};

   my $body  = $part->body;
   my @bodies;

   # Handle multipart parts.

   if($body->isMultipart)
   {   return $matched unless $self->{MBS_multiparts};
       my $no_delayed = not $self->{MBS_delayed};
       @bodies = ($body->preamble, $body->epilogue);

       foreach my $piece ($body->parts)
       {   next unless defined $piece;
           next if $no_delayed && $piece->isDelayed;

           $matched += $self->searchPart($piece);
           return $matched if $matched && !$self->{MBS_details};
       }
   }
   else
   {   @bodies = ($body);
   }

   # Handle normal bodies.

   foreach (@bodies)
   {   next unless defined $_;
       next if !$self->{MBS_binaries} && $_->isBinary;
       my $body   = $self->{MBS_decode} ? $_->decoded : $_;
       my $inbody = $self->inBody($part, $body);
       $matched  += $inbody;
   }

   $matched;
}

#-------------------------------------------

=method inHead PART, HEAD

Tests whether header contains the requesting information.  See the
specific search module for its parameters.

=cut

sub inHead(@) {shift->notImplemented}

#-------------------------------------------

=method inBody PART, BODY

Tests whether body contains the requesting information.  See the
specific search module for its parameters.

=cut

sub inBody(@) {shift->notImplemented}

#-------------------------------------------

=head2 The Results

=cut

#-------------------------------------------

=method printMatch [FILEHANDLE], HASH

Print the information about the match (see C<details> option in the
search() method) in some understandable way.  If no file handle
is specified, the output will go to the selected filehandle (see
C<perldoc -f select>).

=cut

sub printMatch($) {shift->notImplemented}

#-------------------------------------------

1;