package File::Shortcut::App;

use 5.10.0;

use warnings;
use strict;

use Carp;
$SIG{__DIE__} = \&croak;

use Getopt::Long 2.32 qw(:config
  bundling
  no_auto_abbrev
  no_ignore_case
);

use File::Shortcut;


sub _run {
  my($fun, $sub) = (shift, shift);

  my @opts = (
    "debug!" => sub {
      my $dbg = $_[1];
      $File::Shortcut::Debug = $dbg;
      $Carp::Verbose = $dbg;
    },
    @_
  );
  my %opts;
  GetOptions(\%opts, @opts) or die;

  $sub->(sub {
    no strict 'refs';
    &{"File::Shortcut::$fun"}(@_) // die "$File::Shortcut::Error\n";
  }, %opts);
}


sub mkshortcut {
  return _run(shortcut => sub {
    my $call = shift;
    my %opts = @_;

    die unless $ARGV[0];
    die unless $ARGV[1];

    return $call->(@ARGV);
  }, qw(
    description=s
    icon=s
  ));
}

sub readshortcut {
  return _run(readshortcut => sub {
    my $call = shift;
    my %opts = @_;

    die unless $ARGV[0];

    my $result = $call->(@ARGV);
    return unless defined $result;
    say $result;
    return 1;
  }, qw(
    details!
  ));
}

1;
