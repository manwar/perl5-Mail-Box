#!/usr/local/bin/perl -w

#
# Test threading of MH folders.
#

use strict;
use Test;
use lib '..', 't';
use File::Spec;

use Mail::Box::Manager;

use Tools;

BEGIN {plan tests => 4}

my $orig = File::Spec->catfile('t', 'mbox.src');
my $src  = File::Spec->catfile('t', 'mh.src');

clean_dir $src;
unpack_mbox($orig, $src);

my $mgr    = new Mail::Box::Manager;

my $folder = $mgr->open
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , access       => 'rw'
  );

my $threads = $mgr->threads(folder => $folder);

ok($threads->known == 0);

my @all = $threads->sortedAll;
ok(@all == 28);

my $out = join '', map {$_->threadToString} @all;

my @lines = split "\n", $out;
pop @lines;
ok(@lines = $folder->messages);

ok($out eq <<'DUMP');
1.7K Resize with Transparency
2.8K *- Re: File Conversion From HTML to PS and TIFF
3.8K    `--*- Re: File Conversion From HTML to PS and TIFF
3.8K       `- Re: File Conversion From HTML to PS and TIFF
2.8K Transparency question
3.8K RE: Transparency question
4.7K RE: Transparency question
7.0K RE: Transparency question
8.7K RE: Transparency question
4.1K RE: jpeg2000 question
2.9K *- Problem resizing images through perl script
1.4K |  `- Re: Problem resizing images through perl script
3.1K |     `- RE: Problem resizing images through perl script
1.6K |        `- Re: Problem resizing images through perl script
3.3K `- Re: Convert HTM, HTML files to the .jpg format
2.2K Undefined Symbol: SetWarningHandler
1.6K `- Re: Undefined Symbol: SetWarningHandler
3.3K *- Re: watermarks/embossing
1.3K Re: Annotate problems (PR#298)
1.1K `- Re: Annotate problems (PR#298)
2.1K 
1.9K `- Re: your mail
2.5K    `- Re: your mail
3.2K 
1.3K Re: your mail
1.2K `- Re: your mail
1.3K Re: your mail
1.8K Re: your mail
4.9K `- Re: your mail
1.9K mailing list archives
2.8K printing solution for UW 7.1
2.7K delegates.mgk set-up for unixware printing
3.1K *- Re: converts new sharpen factors
2.5K New ImageMagick mailing list
340  subscribe
1.8K Confirmation for subscribe magick-developer
592  `- Re: Confirmation for subscribe magick-developer
 12K Welcome to magick-developer
3.1K core dump in simple ImageMagick example
2.7K `- Re: core dump in simple ImageMagick example
2.1K    `- Re: core dump in simple ImageMagick example
1.3K       `- Re: core dump in simple ImageMagick example
3.4K Core Dump on ReadImage
1.5K `- Re: Core Dump on ReadImage
2.6K Font metrics
DUMP

clean_dir $src;