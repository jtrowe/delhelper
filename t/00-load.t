#!perl -T

use Test::More tests => 2;

BEGIN {
    use_ok( 'Net::Delicious::Checker' ) || print "Bail out!
";
    use_ok( 'Net::Delicious::Checker::Schema' ) || print "Bail out!
";
}

diag( "Testing Net::Delicious::Checker $Net::Delicious::Checker::VERSION, Perl $], $^X" );
diag( "Testing Net::Delicious::Checker::Schema $Net::Delicious::Checker::Schema::VERSION, Perl $], $^X" );
