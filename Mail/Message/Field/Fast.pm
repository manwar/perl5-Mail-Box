use strict;
use warnings;

package Mail::Message::Field::Fast;
use base 'Mail::Message::Field';

use Carp;

=head1 NAME

Mail::Message::Field::Fast - one line of a message header

=head1 SYNOPSIS

 See Mail::Message::Field

=head1 DESCRIPTION

See Mail::Message::Field.  This is the faster, but less flexible
implementation of a header field.  The data is stored in an array,
and some hacks are made to speeds things up.  Be gentle with me, and
consider that each message contains many of these lines, so speed
is very important here.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------
#
# The array is defined as:
#   [ $name, $body, $comment, $folded ]
#   where folded may not be or undef

sub new($;$$@)
{
    my $class  = shift;
    my ($name, $body, $comment);

    if(@_==2 && ref $_[1] eq 'ARRAY' && !ref $_[1][0])
                 { $name = shift }
    elsif(@_>=3) { ($name, $body, $comment) = @_ }
    elsif(@_==2) { ($name, $body) = @_ }
    elsif(@_==1) { $name = shift }
    else         { confess }

    #
    # Compose the body.
    #

    if(!defined $body)
    {   # must be one line of a header.
        ($name, $body) = split /\:\s*/, $name, 2;

        unless($body)
        {   warn "No colon in headerline: $name\n";
            $body = '';
        }
    }
    elsif($name =~ m/\:/)
    {   warn "A header-name cannot contain a colon in $name\n";
        return undef;
    }

    if(defined $body && ref $body)
    {   # Objects
        $body = join ', ',
            map {$_->isa('Mail::Address') ? $_->format : "$_"}
                (ref $body eq 'ARRAY' ? @$body : $body);
    }
    
    warn "Header-field name contains illegal character: $name\n"
        if $name =~ m/[^\041-\176]/;

    $body =~ s/\s*\015?\012$//;

    #
    # Take the comment.
    #

    if(defined $comment && length $comment)
    {   # A comment is defined, so shouldn't be in body.
        warn "A header-body cannot contain a semi-colon in $body."
            if $body =~ m/\;/;
    }
    elsif(__PACKAGE__->isStructured($name))
    {   # try strip comment from field-body.
        ($body, $comment) = split /\s*\;\s*/, $body, 2;
    }

    #
    # Create the object.
    #

    bless [$name, $body, $comment], $class;
}

#------------------------------------------

=head2 The Field

=cut

#------------------------------------------

sub clone()
{   my $self = shift;
    bless [ @$self ], ref $self;
}

#------------------------------------------

=head2 Access to the Field

=cut

#------------------------------------------

sub name() { lc shift->[0] }

#------------------------------------------

sub body() {    shift->[1] }

#------------------------------------------

sub comment(;$)
{   my $self = shift;
    @_ ? $self->[2] = shift : $self->[2];
}

#------------------------------------------

sub content()
{   my $self = shift;
    return $self->[1] unless defined $self->[2];
    "$self->[1]; $self->[2]";
}

#------------------------------------------

sub folded(;$)
{   my $self = shift;
    if(@_)
    {   return unless defined($self->[3] = shift);
        return @{$self->[3]};
    }
    return @{$self->[3]} if defined $self->[3];

      defined $self->[2]
    ? "$self->[0]: $self->[1]; $self->[2]\n"
    : "$self->[0]: $self->[1]\n";
}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

sub newNoCheck($$$;$)
{   my $class = shift;
    bless [ @_ ], $class;
}

#------------------------------------------

1;