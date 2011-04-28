package File::Shortcut::Util;

use 5.10.0;

use warnings;
use strict;

use parent qw(Exporter);
our @EXPORT_OK = qw(
  err
  expect

  dbg

  sizeof
  map_bits
  parse_filetime
);

use Carp;

use File::Shortcut;


sub err {
  local $SIG{__WARN__} = \&confess;
  $File::Shortcut::Error = sprintf(shift, @_);
  return undef;
}

sub expect {
  my($where, $format, $value, $expect) = @_;
  return 1 if ($value ~~ $expect);
  return _err("%s: expected $format, got $format",
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
  my $type = shift;
  return length(pack("x[$type]"));
}


sub map_bits {
  my $value = shift;

  my %result = (
    _raw => $value,
  );

  while (@_) {
    my $key = shift;
    next unless $key;
    $result{$key} = $value & 1;
    $value >>= 1;
  }

  return \%result;
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
