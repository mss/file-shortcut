package File::Shortcut::Writer;

use 5.10.0;

use warnings;
use strict;

use Carp;

use File::Shortcut;
use File::Shortcut::Util qw(
  err expect dbg
);


sub write_shortcut {
  my($source, $target, $options) = @_;
  my $dbg = $File::Shortcut::Debug;

  #TODO
  die "write_shortcut() not implemented";
}

1;
