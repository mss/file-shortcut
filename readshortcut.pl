#!/usr/bin/perl
#

use 5.10.0;

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use File::Shortcut qw(readshortcut);

use Data::Dumper;

$File::Shortcut::debug = 1;

my $data = readshortcut(@ARGV);
unless ($data) {
  say $File::Shortcut::errstr;
  exit 1;
}
print Dumper($data);
