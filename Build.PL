use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Net::Delicious::Checker',
    license             => 'perl',
    dist_author         => q{Joshua T. Rowe <jrowe@jrowe.org>},
    dist_version_from   => 'lib/Net/Delicious/Checker.pm',
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'Net-Delicious-Checker-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
