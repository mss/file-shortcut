package File::Shortcut::Util;

use 5.10.0;

use warnings;
use strict;

use parent qw(Exporter);
our @EXPORT_OK = do {
  # All subs except private ones are fine to be imported somewhere else.
  # Based on http://stackoverflow.com/questions/607282/-/607342#607342
  no strict 'refs';
  my $P = __PACKAGE__ . "::";
  grep {
    my $N = "$P$_";
    defined &{$N} and $N !~ /^_/;
  } keys %{$P}
};

use Carp;

use File::Shortcut;


sub err {
  local $SIG{__WARN__} = $File::Shortcut::Debug ? \&croak : \&carp;
  $File::Shortcut::Error = sprintf(shift, @_);
  croak \$File::Shortcut::Error;
}

sub expect {
  my($where, $format, $value, $expect) = @_;
  return 1 if ($value ~~ $expect);
  err("%s: expected $format, got $format",
    $where,
    $expect,
    $value,
  );
}


sub dbg {
  my $fh = $File::Shortcut::Debug;
  return unless $fh;
  $fh = \*STDERR unless ref $fh;
  printf $fh shift() . "\n", @_;
}




sub sizeof {
  my $template = shift;
  return length(pack("x[$template]"));
}


sub unpack_bits {
  my $value = shift;

  my %result = (
    _raw => $value,
  );

  foreach my $key (@_) {
    $result{$key} = $value & 1;
    $value >>= 1;
  }
  delete $result{_};

  return \%result;
}

sub pack_bits {
  my @keys = @{shift()};

  my $result = 0;

  my %bits = map { $_ => 1 } @_;
  foreach my $key (reverse(@keys)) {
    $result <<= 1;
    next if $key eq "_";
    $result |= $bits{$key} || 0;
  }

  return $result;
}


sub parse_filetime {
  # Windows epoch: 1601-01-01.  Precision: 100ns
  # http://msdn.microsoft.com/en-us/library/ms724284.aspx
  # Loosely based on
  #  * DateTime::Format::WindowsFileTime 0.02
  #  * http://www.perlmonks.org/?node_id=846055
  #  * http://stackoverflow.com/questions/1864245/how-can-i-do-64-bit-arithmetic-in-perl
  use bignum;

  my $value = shift;

  my($lo, $hi) = unpack 'VV' => $value;
  $value = $hi * 2**32 + $lo;

  # Fix the epoch.
  $value -= 11644473600 * 1e7;
  # Centi-nanoseconds to seconds.
  $value /= 1e7;

  no bignum;
  return $value->bstr() * 1;
}

1;
