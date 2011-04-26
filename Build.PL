use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'File::Shortcut',
    license             => 'perl',
    dist_author         => q{Malte S. Stretz <mss@apache.org>},
    dist_version_from   => 'lib/File/Shortcut.pm',
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'File-Shortcut-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
