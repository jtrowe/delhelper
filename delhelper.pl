#!/usr/bin/perl

package Schema;

use base qw( DBIx::Class::Schema::Loader );

__PACKAGE__->loader_options(
#    debug => 1
);

1;

package main;

use strict;
use warnings;

use DBI;
use XML::DOM::XPath;
use LWP::UserAgent;

my $schema = Schema->connect('dbi:SQLite:dbname=db', '', '');

my @posts = getUnchecked2(100);
check(@posts);

sub getUnchecked2 {
    my $limit = shift || 100;

    my @unchecked;

    my @posts = $schema->resultset('Post')->search(undef, {
        order_by => 'random()'
    });

    foreach my $post ( @posts ) {
        my $checked = $schema->resultset('Response')->search({
            href => $post->href,
        })->next;

        unless ( $checked ) {
            push @unchecked, $post;
        }

        if ( @unchecked > $limit ) {
            last;
        }
    }

    return @unchecked;
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

sub check {
    my $agent = LWP::UserAgent->new;
    $agent->agent('Link Checker/0.10');
    $agent->from('jrowe@jrowe.org');
    $agent->max_redirect(0);
    $agent->timeout(5);

    foreach ( @_ ) {
        my $href = $_->href;
        my $response = $agent->head($href);
        my $code = $response->code;
        $schema->resultset('Response')->create({
            href        => $href,
            code        => $code,
            seconds1970 => time,
        });

        print $code . ' ' . $href . "\n";
    }
}

sub file {
    my $dir = join '/', $ENV{'HOME'},
            qw( Desktop Documents Backups delicious );

    my $DIR;
    opendir $DIR, $dir;
    my @files = map { join '/', $dir, $_ } grep { m/\.xml$/ } readdir $DIR;
    closedir $DIR;

    return $files[0];
}

sub load {
    my @COLS = qw( href time hash description tag extended meta );
#    $db->do(q|
#        CREATE TABLE post (
#            href TEXT,
#            time TEXT,
#            hash TEXT,
#            description TEXT,
#            tag TEXT,
#            extended TEXT,
#            meta TEXT
#        );
#    |);

    my $file = file();
    my $parser = XML::DOM::Parser->new;
    my $doc = $parser->parsefile($file);

    my $years = {};

    my $sql = sprintf(
            'INSERT INTO post ( %s ) VALUES ( %s )',
            join(', ', @COLS), join(', ', ( map { '?' } @COLS )));
    #print $sql . "\n";
    my $sthI = $db->prepare($sql);

    my @nodes = $doc->findnodes('/posts/post');
    my $i = 0;
    foreach ( @nodes ) {
        my @vals;
        foreach my $c ( @COLS ) {
            push @vals, $_->getAttribute($c);
        }

        $sthI->execute(@vals);

    }
}

__END__
load();

#$db->do(q|
#    CREATE TABLE post (
#        href TEXT NOT NULL UNIQUE,
#        year INT NOT NULL,
#        month INT NOT NULL
#    );
#    CREATE TABLE processed (
#        href TEXT NOT NULL UNIQUE
#    );
#|);
#my $sthIns = $db->prepare(
#        q|INSERT INTO post ( href, year, month ) VALUES ( ?, ?, ? )|);
#unless ( $sthIns ) {
#    print STDERR 'ERROR: Cannot create prepared statement: '
#            . $db->errstr . "\n";
#
#    exit 1;
#}

my $sthGetCount = $db->prepare(
        q|SELECT count(*) FROM post WHERE href NOT IN (
            SELECT href FROM processed
          )
        |);
my $sthInsProcessed = $db->prepare(
        q|INSERT INTO processed ( href ) VALUES ( ? )|);

#dump();


$db->disconnect;

sub file {
    my $dir = join '/', $ENV{'HOME'},
            qw( Desktop Documents Backups delicious );

    my $DIR;
    opendir $DIR, $dir;
    my @files = map { join '/', $dir, $_ } grep { m/\.xml$/ } readdir $DIR;
    closedir $DIR;

    return $files[0];
}

sub load {
    $db->do(q|
        DROP TABLE post;
    |);
    my @COLS = qw( href time hash description tag extended meta );
    $db->do(q|
        CREATE TABLE post (
            href TEXT,
            time TEXT,
            hash TEXT,
            description TEXT,
            tag TEXT,
            extended TEXT,
            meta TEXT
        );
    |);

    my $file = file();
    my $parser = XML::DOM::Parser->new;
    my $doc = $parser->parsefile($file);

    my $years = {};

    my $sql = sprintf(
            'INSERT INTO post ( %s ) VALUES ( %s )',
            join(', ', @COLS), join(', ', ( map { '?' } @COLS )));
    #print $sql . "\n";
    my $sthI = $db->prepare($sql);

    my @nodes = $doc->findnodes('/posts/post');
    my $i = 0;
    foreach ( @nodes ) {
        my @vals;
        foreach my $c ( @COLS ) {
            push @vals, $_->getAttribute($c);
        }

        $sthI->execute(@vals);

    }
}

sub dump {
    $sthGetCount->execute;
    my ( $count ) = $sthGetCount->fetchrow_array;
    print $count . ' unprocessed hrefs.' . "\n";

    my $min = 20;
    my $max = 100;

    my $limit = $count / 10;
    if ( $limit < $min ) {
        $limit = $min;
    }
    elsif ( $limit > $max ) {
        $limit = $max;
    }

    my @ltime = localtime time;
    my $cyear = sprintf '%02d', $ltime[5];
    my $cmonth = 1900 + $ltime[4];

    my $sthGetHrefs = $db->prepare(
            q|SELECT href FROM post WHERE href NOT IN (
                SELECT href FROM processed
              )
              AND month != ? AND year != ?
              ORDER BY random()
              LIMIT ?
            |);

    $sthGetHrefs->execute($limit, $cmonth, $cyear);

    print q|<html><body><ul>|;
    while ( my ( $href ) = $sthGetHrefs->fetchrow_array ) {
        print '<li>';
        print '<a href="' . $href . '">' . $href . '</a>' . "\n";
        print '</li>';

        my $url = qq|https://api.del.icio.us/v1/posts/delete?url=$href|;
        print '  <a href="' . $url . '">Delete</a>' . "\n";

        $sthInsProcessed->execute($href);
    }
    print q|</ul></body></html>|;
}

