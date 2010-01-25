#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use XML::DOM::XPath;

my $db = DBI->connect('dbi:SQLite:dbname=db', '', '');
#$db->do(q|
#    DROP TABLE post;
#|);
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
my $sthIns = $db->prepare(
        q|INSERT INTO post ( href, year, month ) VALUES ( ?, ?, ? )|);
unless ( $sthIns ) {
    print STDERR 'ERROR: Cannot create prepared statement: '
            . $db->errstr . "\n";

    exit 1;
}

my $sthGetCount = $db->prepare(
        q|SELECT count(*) FROM post WHERE href NOT IN (
            SELECT href FROM processed
          )
        |);
my $sthInsProcessed = $db->prepare(
        q|INSERT INTO processed ( href ) VALUES ( ? )|);

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
    print '<li><a href="' . $href . '">' . $href . '</a></li>' . "\n";
    $sthInsProcessed->execute($href);
}
print q|</ul></body></html>|;

#load();

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
    my $file = file();
    my $parser = XML::DOM::Parser->new;
    my $doc = $parser->parsefile($file);

    my $years = {};

    my @nodes = $doc->findnodes('/posts/post');
    my $i = 0;
    foreach ( @nodes ) {
        my $timeS = $_->getAttribute('time');

        unless ( $timeS =~ m/^(\d{4})-(\d{2})/ ) {
            next;
        }

        my $year = $1;
        my $month = $2;

        $sthIns->execute($_->getAttribute('href'), $year, $month);

    #    print $timeS, "\n";
    #    print $year, "\n";

    #    push @{ $years->{$year}->{$month} ||= [] }, $_;

    #    if ( $i++ > $limit ) {
    #        last;
    #    }
    }
}

