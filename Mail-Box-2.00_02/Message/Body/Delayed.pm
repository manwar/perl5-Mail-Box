use strict;
use warnings;

package Mail::Message::Body::Delayed;
use base 'Mail::Reporter';

use 'Mail::Message::Body';  # only simulated relationship

our $VERSION = '2.00_02';

=head1 NAME

Mail::Message::Body::Delayed - Body of a Mail::Message but not read yet.

=head1 SYNOPSIS

   my $body  = $msg->body;
   my $text  = $body->string;
   my @text  = $body->lines;
   my FileHandle $file = $body->file;
   $body->print(\*FILE);

=head1 DESCRIPTION

READ C<Mail::Message::Body> FIRST.  Message bodies of this type will be
replaced by an other type on the moment you access the content.  In this
manual-page you find the description of how message-body get delay-loaded.

=head1 GENERAL METHODS

=over 4

=cut

sub isDelayed() {1}

sub isMultipart()
{   # multipart info can be derived from header, which may avoid
    # parsing the body.

    my $type = shift->{MMBD_message}->head->get('Content-Type');
    $type && $type =~ m[^multipart/]i;
}

#------------------------------------------

our $AUTOLOAD;
sub AUTOLOAD
{   my $self   = shift;
    (my $call = $AUTOLOAD) =~ s/.*\:\://;

    no strict 'refs';
    $self->{MMBD_message}->loadBody->call(@_);
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

L<Mail::Message>
L<Mail::Message::Body>
L<Mail::Box::Manager>

=cut

1;