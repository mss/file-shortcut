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

use Data::Dumper;

$File::Shortcut::Debug = 1;

my $data = readshortcut(@ARGV);
unless ($data) {
  say $File::Shortcut::Error;
  exit 1;
}
print Dumper($data);
