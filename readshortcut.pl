#!/usr/bin/perl
#

use 5.10.0;

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use File::Shortcut;

File::Shortcut::read_shortcut(@ARGV);
