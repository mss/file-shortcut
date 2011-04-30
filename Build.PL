#!/usr/bin/perl
use strict;
use warnings;
use Module::Build;
use Data::Dumper;
use FindBin qw($Bin);

my %builder = (
  module_name         => 'File::Shortcut',
  dist_author         => q{Malte S. Stretz <mss}.chr(64).q{apache.org>},
  dist_version_from   => 'lib/File/Shortcut.pm',
  release_status      => 'unstable',
  license             => 'perl',
  create_license      => 1,
  create_readme       => 1,

  # core modules shipped with 5.10 omitted
  requires => {
    'perl' => '5.10.0',
    'Try::Tiny' => 0,
  },
  configure_requires => {
    'Module::Build' => 0.34,
    do { -e "$Bin/README" ? () : ('Pod::Readme' => 0) },
    do { -e "$Bin/LICENSE" ? () : ('Software::License' => 0) },
  },

  PL_files           => { 'Bin.PL' => [ qw(
    bin/mkshortcut
    bin/readshortcut
  )]},
  add_to_cleanup     => [ 'File-Shortcut-*' ],
  create_makefile_pl => 'traditional',
);
Module::Build->new(%builder)->create_build_script();
