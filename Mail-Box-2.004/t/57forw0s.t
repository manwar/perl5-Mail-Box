#!/usr/bin/perl -w
#
# Test the creation of forward subjects
#

use Test;
use strict;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message::Construct;
use Tools;

BEGIN {plan tests => 7}

ok(Mail::Message->forwardSubject('subject') eq 'Forw: subject');
ok(Mail::Message->forwardSubject('Re: subject') eq 'Forw: Re: subject');
ok(Mail::Message->forwardSubject('Re[2]: subject') eq 'Forw: Re[2]: subject');
ok(Mail::Message->forwardSubject('subject (forw)') eq 'Forw: subject (forw)');
ok(Mail::Message->forwardSubject('subject (Re)') eq 'Forw: subject (Re)');
ok(Mail::Message->forwardSubject(undef) eq 'Forwarded');
ok(Mail::Message->forwardSubject('') eq 'Forwarded');
