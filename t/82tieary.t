#!/usr/bin/perl

#
# Test access to folders using ties.
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);

use Tools;
use Mail::Box::Mbox;
use Mail::Box::Tie::ARRAY;
use Mail::Message::Construct;

BEGIN {plan tests => 13}

#
# The folder is read.
#

my $folder = new Mail::Box::Mbox
  ( folder    => $src
  , folderdir => 't'
  , lock_type => 'NONE'
  , extract   => 'ALWAYS'
  , access    => 'rw'
  );

ok(defined $folder);
cmp_ok($folder->messages, "==", 45);

tie my(@folder), 'Mail::Box::Tie::ARRAY', $folder;
cmp_ok(@folder , "==",  45);

is($folder->message(4), $folder[4]);

ok(! $folder->message(2)->deleted);
$folder[2]->delete;
ok($folder->message(2)->deleted);
cmp_ok(@folder , "==",  45);

ok(! $folder->message(3)->deleted);
my $d3 = delete $folder[3];
ok(defined $d3);
ok($folder->message(3)->deleted);

# Double messages will not be added.
push @folder, $folder[1]->clone;
cmp_ok(@folder , "==",  45);

# Different message, however, will be added.
push @folder, Mail::Message->build(data => []);

cmp_ok($folder->messages , "==",  46);
cmp_ok(@folder , "==",  46);

$folder->close(write => 'NEVER');
exit 0;
