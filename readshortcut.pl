#!/usr/bin/perl
#

use 5.10.0;

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use File::Shortcut qw(read_shortcut);

use Data::Dumper;

my $data = read_shortcut(@ARGV);
unless ($data) {
  say $File::Shortcut::errstr;
  exit 1;
}
print Dumper($data);
