#!/usr/bin/perl

=head1 DESCRIPTION

This script loads an XML dump of a users delicious.com bookmarks
into a database and performs various processes upon it.

It can check link validity.
It can create a report detailing unreachable links.
It can create a listing of tags which seem to be plural.

Sample command lines:

    Load sample.xml into the SQLite database 'db'.
    perl delhelper.pl --db db --input sample.xml --load

    Check the links.
    perl delhelper.pl --db db --check 20

    Create the report (probably will not be any)
    perl delhelper.pl --username $u --password $p --db db --report report.html

    List possible plural tags
    perl delhelper.pl --db db --tags


=head1 AUTHOR

Joshua T. Rowe <jrowe@jrowe.org>

=cut


package main;

use strict;
use warnings;

use DBI;
use Getopt::Long;
use Net::Delicious::Checker;
use Net::Delicious::Checker::Schema;
use LWP::UserAgent;

my $username = 'username';
my $password = 'password';
my %opts = (
    db     => 'db',
    check  => 20,
    init   => 0,
    input  => 'sample.xml',
    load   => 0,
    report => 0,
    tags   => 0,
);


GetOptions(
    'db=s'       => \$opts{'db'},
    'init'       => \$opts{'init'},
    'input=s'    => \$opts{'input'},
    'check=i'    => \$opts{'check'},
    'load!'      => \$opts{'load'},
    'report=s'   => \$opts{'report'},
    'tags'       => \$opts{'tags'},

    'username=s' => \$username,
    'password=s' => \$password,
);

Net::Delicious::Checker->new;

unless ( -e $opts{'db'} ) {
    Net::Delicious::Checker->initDataStore($opts{'db'});
}

my $schema = Net::Delicious::Checker::Schema->connect(
        'dbi:SQLite:dbname=' . $opts{'db'}, '', '');

if ( $opts{'tags'} ) {
    tagReport();
}

if ( $opts{'report'} ) {
    report($opts{'report'}, 30);
}

if ( $opts{'check'} ) {
    Net::Delicious::Checker->check($schema, $opts{'check'});
}

if ( $opts{'load'} ) {
    load();
}

sub getChecked {
    my $limit = shift || 100;

    my @checked;

    my @responses = $schema->resultset('Response')->search(undef,
    {
        limit    => $limit,
        order_by => 'random()'
    }
    )->all;

    my %SKIP = map { $_ => 1 } qw( 200  301 302 );
    foreach my $response ( @responses ) {
        if ( $SKIP{$response->code} ) {
            next;
        }

        push @checked, $response;

        if ( @checked >= $limit ) {
            last;
        }
    }

    return @checked;
}

sub getUnchecked {
    my ( $limit ) = @_;

    #First trying a subquery that will be basically empty
    my $rs = $schema->resultset('Response')->search({
        href => 'http://example.com/',
    });

    return $schema->resultset('Post')->search(
#        href => 'http://slashdot.org/',
        href => {
            'NOT IN' => $rs->get_column('href')->as_query
        },
    );
}

sub file {
    my $dir = join '/', $ENV{'HOME'},
            qw( Desktop Documents Backups delicious );

    my $DIR;
    opendir $DIR, $dir;
    my @files = grep { m/\.xml$/ } readdir $DIR;
    closedir $DIR;

    my $file = $schema->resultset('File')->search({
        file => $files[0],
        processed => 1,
    })->next;
    if ( $file ) {
        print 'File ' . $files[0] . ' already processed.' . "\n";
        return;
    }

    return join '/', $dir, $files[0];
}

sub load {
    my $file;
    if ( $opts{'input'} ) {
        $file = $opts{'input'};
    }
    else {
        $file = file();

        unless ( $file ) {
            return;
        }
    }

    Net::Delicious::Checker->load($schema, $file);
}

sub report {
    my $file = shift;
    my $limit = shift;

    my $OUT;
    open $OUT, '>', $file;
    print $OUT q|<html><body><ul>|;
    my @responses = getChecked($limit);

    print 'Found ' . scalar(@responses) . ' posts for the report.' . "\n";

    foreach my $response ( @responses ) {
        my $code = $response->code;
        my $href = $response->href;

        my $post = $schema->resultset('Post')->search({
            href => $href,
        })->next;

        print $OUT '<li>';
        print $OUT $code . ' ';
        print $OUT '<a href="' . $href . '">' . $href . '</a>' . "\n";

        my $url = 'https://' . $username . ':' . $password
                . '@api.del.icio.us/v1/posts/delete?url='
                . $href;
        print $OUT '  <a href="' . $url . '">Delete</a>' . "\n";

        $url = 'http://delicious.com/url/' . $post->hash;
        print $OUT '  <a href="' . $url . '">Info</a>' . "\n";

        print $OUT '</li>';

        $schema->resultset('Processed')->find_or_create({
            href => $href,
        });
    }
    print $OUT q|</ul></body></html>|;
}

sub tagReport {
    my %tags;

    foreach my $post ( $schema->resultset('Post')->all ) {
        foreach my $t ( split /\s+/, $post->tag ) {
            $tags{$t} = 1;
        }
    }

    my @tags = keys %tags;
    my @endInS = grep { /s$/ } @tags;

    print scalar(@tags) . ' unique tags' . "\n";

    print scalar(@endInS) . ' in in "s":' . "\n";
    print join('    ', @endInS) . "\n";

}

