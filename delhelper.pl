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
use File::Basename;
use Getopt::Long;
use XML::DOM::XPath;
use LWP::UserAgent;

my $schema = Schema->connect('dbi:SQLite:dbname=db', '', '');

my %opts = (
    check => 200,
    load => 0,
    report => 0,
);

GetOptions(
    'check=i'  => \$opts{'check'},
    'load!'    => \$opts{'load'},
    'report=s' => \$opts{'report'},
);

if ( $opts{'report'} ) {
    report($opts{'report'}, 30);
}

if ( $opts{'check'} ) {
    my @posts = getUnchecked2($opts{'check'});
    check(@posts);
}

if ( $opts{'load'} ) {
    load();
}

sub getUnchecked2 {
    my $limit = shift;

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

        if ( ( $limit ) && ( @unchecked >= $limit ) ) {
            last;
        }
    }

    return @unchecked;
}

sub getChecked2 {
    my $limit = shift || 100;

    my @checked;

    my @responses = $schema->resultset('Response')->search(undef,
    {
        limit    => $limit,
        order_by => 'random()'
    }
    )->all;

    foreach my $response ( @responses ) {
        if ( $response->code eq '200' ) {
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

sub check {
    my $agent = LWP::UserAgent->new;
    $agent->agent('Link Checker/0.10');
    $agent->from('jrowe@jrowe.org');
    $agent->max_redirect(0);
    $agent->timeout(5);

    print 'Checking ' . scalar(@_) . ' posts.' . "\n";

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
    my @COLS = qw( href time hash description tag extended meta );

    my $file = file();

    unless ( $file ) {
        return;
    }
    my $parser = XML::DOM::Parser->new;
    my $doc = $parser->parsefile($file);

    my $years = {};

    my @nodes = $doc->findnodes('/posts/post');
    my $i = 0;
    foreach ( @nodes ) {
        my $args;
        foreach my $c ( @COLS ) {
            $args->{$c} = $_->getAttribute($c);
        }

        $schema->resultset('Post')->create($args);
    }

    my ( $basename ) = fileparse($file);

    $schema->resultset('File')->create({
        file => $basename,
        processed => 1,
    });
}

sub report {
    my $file = shift;
    my $limit = shift;

    my $OUT;
    open $OUT, '>', $file;
    print $OUT q|<html><body><ul>|;
    my @responses = getChecked2($limit);

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

        my $url = 'https://jrowe:m0j0ni%on@api.del.icio.us/v1/posts/delete?url='
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

