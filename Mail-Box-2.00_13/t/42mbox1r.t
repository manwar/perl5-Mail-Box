#!/usr/bin/perl -w
#
# Test reading of mbox folders.
#

use Test;
use strict;
use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Box::Mbox;
use Tools;

use File::Compare;
use File::Spec;

BEGIN {plan tests => 9}

my @src = (folder => '=mbox.src', folderdir => 't');

warn "   * Mbox status BETA\n";
ok(Mail::Box::Mbox->foundIn(@src));

#
# The folder is read.
#

my $folder = new Mail::Box::Mbox
  ( @src
  , lock_type    => 'NONE'
  , lazy_extract => 'NEVER'
  );

ok(defined $folder);
ok($folder->messages == 45);
ok($folder->organization eq 'FILE');

#
# Extract one message.
#

my $message = $folder->message(2);
ok(defined $message);
ok($message->isa('Mail::Box::Message'));

#
# All message should be parsed.
#

my $parsed = 1;
$parsed &&= $_->isParsed foreach $folder->messages;
ok($parsed);

#
# Try to delete a message
#

$folder->message(2)->delete;
ok($folder->messages == 44);
ok($folder->allMessages == 45);

exit 0;