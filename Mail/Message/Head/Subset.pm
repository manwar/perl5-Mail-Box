
use strict;

package Mail::Message::Head::Subset;

use base 'Mail::Message::Head';

use Object::Realize::Later
    becomes        => 'Mail::Message::Head::Complete',
    realize        => 'load',
    believe_caller => 1;

use Carp;
use Date::Parse;

=head1 NAME

Mail::Message::Head::Subset - subset of header information of a message

=head1 SYNOPSIS

 my Mail::Message::Head::Subset $subset = ...;
 $subset->isa('Mail::Message::Head')  # true
 $subset->guessBodySize               # integer or undef
 $subset->isDelayed                   # true

=head1 DESCRIPTION

Some types of folders contain an index file which lists a few lines of
information per messages.  Especially when it is costly to read header lines,
the index speeds-up access considerably.  For instance, the subjects of
all messages are often wanted, but waiting for a thousand messages of the
folder to be read may imply a thousand network reads (IMAP) or file
openings (MH)

When you access header fields which are not in the header subset, the whole
header has to be parsed (which may consume considerable time, depending on
the type of folder).

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

=cut

#-------------------------------------------

=head2 Constructing a Header

=cut

#-------------------------------------------

=get NAME [,INDEX]

Get the data which is related to the field with the NAME.  The case of the
characters in NAME does not matter.  When a NAME is used which is not known
yet, realization will take place.

=cut

sub get($;$)
{   my $self = shift;
 
    if(wantarray)
    {   my @values = $self->SUPER::get(@_);
        return @values if @values;
    }
    else
    {   my $value  = $self->SUPER::get(@_);
        return $value  if $value;
    }

    $self->load->get(@_);
}

#-------------------------------------------

=head2 Access to the Header

=cut

#-------------------------------------------

=method count NAME

Count the number of fields with this NAME.  If the NAME cannot be found,
the full header get loaded.  In case we find any NAME field, it is
decided we know all of them, and loading is not needed.

=cut

sub count($)
{   my ($self, $name) = @_;

    my @values = $self->get($name);

    return $self->load->count($name)
       unless @values;

    scalar @values;
}

#-------------------------------------------


=method guessBodySize

The body size is defined in the C<Content-Length> field.  However, this
field may not be known.  In that case, a guess is made based on the known
C<Lines> field.  When also that field is not known yet, C<undef> is returned.

=cut

sub guessBodySize()
{   my $self = shift;

    my $cl = $self->SUPER::get('Content-Length');
    return $1 if defined $cl && $cl =~ m/(\d+)/;

    my $lines = $self->SUPER::get('Lines');   # 40 chars per lines
    return $1*40 if defined $lines && $lines =~ m/(\d+)/;

    undef;
}

#-------------------------------------------
# Be careful not to trigger loading: this is not the thoroughness
# we want from this method.

sub guessTimestamp()
{   my $self = shift;
    return $self->{MMHS_timestamp} if $self->{MMHS_timestamp};

    my $stamp;
    if(my $date = $self->SUPER::get('date'))
    {   $stamp = str2time($date, 'GMT');
    }

    unless($stamp)
    {   foreach ($self->SUPER::get('received'))
        {   $stamp = str2time($_, 'GMT');
            last if $stamp;
        }
    }

    $self->{MMHS_timestamp} = $stamp;
}

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

sub load() {confess;$_[0] = $_[0]->message->loadHead}

#------------------------------------------

1;
