#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Net::Delicious::Checker' ) || print "Bail out!
";
}

diag( "Testing Net::Delicious::Checker $Net::Delicious::Checker::VERSION, Perl $], $^X" );
