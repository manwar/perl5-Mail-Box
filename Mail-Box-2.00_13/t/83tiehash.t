#!/usr/bin/perl -w

#
# Test access to folders using ties on hashes.
#

use strict;
use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::Mbox;
use Mail::Box::Tie::HASH;
use Mail::Message::Construct;
use Tools;

use Test;

BEGIN {plan tests => 99}

my $src  = File::Spec->catfile('t', 'mbox.src');

#
# The folder is read.
#

my $folder = new Mail::Box::Mbox
  ( folder       => $src
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , lazy_extract => 'NEVER'
  );

ok(defined $folder);

tie my(%folder), 'Mail::Box::Tie::HASH', $folder;
ok(keys %folder == 45);
ok(! defined $folder{not_existing});

my @keys = keys %folder;
foreach (@keys)
{   ok(defined $folder{$_});
    my $msg = $folder{$_};
    ok($folder{$_}->messageID eq $_);
}

my $msg   = $folder->message(4);
my $msgid = $msg->messageID;
ok($msg eq $folder{$msgid});

# delete $folder[2];    works for 5.6, but not for 5.5
ok(!$folder->message(4)->deleted);
$folder{$msgid}->delete;
ok($folder->message(4)->deleted);
ok(keys %folder == 45);

# Double messages will not be added.
$folder{ (undef) } = $folder{$msgid}->clone;
ok(keys %folder == 45);

# Different message, however, will be added.
my $newmsg = Mail::Message->build(data => [ 'empty' ]);
$folder{undef} = $newmsg;
ok($folder->allMessages == 46);

exit 0;