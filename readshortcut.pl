#!/usr/bin/perl
#

use 5.10.0;

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use Carp;
$Carp::Verbose = 1;
$SIG{__DIE__} = \&croak;

use File::Shortcut qw(readshortcut);
$File::Shortcut::Debug = 1;

use Data::Dumper;

my $data = readshortcut(@ARGV);
unless ($data) {
  printf STDERR "error: %s\n", $File::Shortcut::Error;
  exit 1;
}
print Dumper($data);
