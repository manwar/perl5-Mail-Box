use strict;
use warnings;

package Mail::Transport::Sendmail;
use base 'Mail::Transport::Send';

use Carp;

=head1 NAME

Mail::Transport::Sendmail - transmit messages using external Sendmail program

=head1 SYNOPSIS

 my $sender = Mail::Transport::Sendmail->new(...);
 $sender->send($message);

=head1 DESCRIPTION

Implements mail transport using the external C<'Sendmail'> program.
When instantiated, the mailer will look for the binary in specific system
directories, and the first version found is taken.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=default via 'sendmail'

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{via} = 'sendmail';

    $self->SUPER::init($args);

    $self->{MTS_program}
      = $args->{proxy}
     || $self->findBinary('sendmail')
     || return;

    $self;
}

#------------------------------------------

=head2 Sending Mail

=cut

#------------------------------------------

sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $program = $self->{MTS_program};
    if(open(MAILER, '|-')==0)
    {   { exec $program, '-t'; }
        $self->log(NOTICE => "Errors when opening pipe to $program: $!");
        return 0;
    }
 
    $self->putContent($message, \*MAILER);

    unless(close MAILER)
    {   $self->log(NOTICE => "Errors when closing $program: $!");
        $? ||= $!;
        return 0;
    }

    1;
}

#------------------------------------------

1;