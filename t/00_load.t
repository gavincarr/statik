#!perl

use Test::More tests => 1;

BEGIN {
    use_ok( 'Statik' ) || print "Bail out!
";
}

diag( "Testing Statik $Statik::VERSION, Perl $], $^X" );
