#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'File::Shortcut' ) || print "Bail out!
";
}

diag( "Testing File::Shortcut $File::Shortcut::VERSION, Perl $], $^X" );
