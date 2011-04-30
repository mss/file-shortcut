#!/usr/bin/perl

use 5.010;

use strict;
use warnings;

use Carp;
use Fcntl;

use File::Spec;

use FindBin qw($Bin);
BEGIN { chdir($Bin) or die "chdir($Bin): $!" };

use lib "lib";
use File::Shortcut;
my $lib = "File::Shortcut";

my $version = $File::Shortcut::VERSION;
my $data = tell(DATA);
my $file = File::Spec->catfile($Bin, __FILE__);
my $date = sprintf("%02d-%02d-%dT%02d:%02d:%02dZ", eval {
  @_ = reverse((gmtime())[0..5]); $_[0] += 1900; $_[1]++; return @_ });
foreach my $bin (@ARGV) {
  my @app = split m{/} => $bin;
  my $app = pop @app;
  my $dir = File::Spec->catdir(@app);
  -d $dir or mkdir($dir) or die "mkdir($dir): $!";
  seek(DATA, $data, Fcntl::SEEK_SET) or die "seek(DATA): $!";
  open(my $fh, '>', $bin) or die "open($bin): $!";
  foreach (<DATA>) {
    no strict 'refs';
    s/(\$\{.*?\})/$1/eeg;
    print $fh $_;
  }
  close($fh) or die "close($bin): $!";
  chmod(0755, $bin) or die "chmod($bin): $!";
}

__DATA__
#!/usr/bin/perl
# Generated for ${app} ${version}
#   by ${file}
#   at ${date}
use strict;
use warnings;
use File::Spec;
use FindBin qw($Bin);
BEGIN {
  $_ = File::Spec->catdir($Bin, File::Spec->updir, "lib");
  unshift @INC, $_ if -d $_ and -f File::Spec->catfile($_, split("::", "${lib}"), "App.pm");
}
use ${lib} ${version};
use ${lib}::App;
${lib}::App::${app};
exit 0;
