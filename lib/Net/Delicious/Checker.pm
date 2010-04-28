package Net::Delicious::Checker;

use warnings;
use strict;

use Data::Dumper;
use File::Basename;
use XML::DOM::XPath;

=head1 NAME

Net::Delicious::Checker - Checks delicious.com bookmarks.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Net::Delicious::Checker;

    my $foo = Net::Delicious::Checker->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 load

Loads a delicious.com XML file into the data store.

=cut

sub load {
    my ( $class, $schema, $file ) = @_;

    print 'Loading file ' . $file . "\n";

    my @COLS = qw( href time hash description tag extended meta );

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

        my $ok = eval {
            $schema->resultset('Post')->create($args);
            1;
        };
        if ( ( ! $ok ) || $@ ) {
            print 'ERROR: Error inserting post [ ' . $@ . ' ]' . "\n";
            print 'post: ' . Dumper($args) . "\n";
        }

    }

    my ( $basename ) = fileparse($file);

    $schema->resultset('File')->create({
        file => $basename,
        processed => 1,
    });
}


=head2 initDataStore

Initializes the data store.

=cut

sub initDataStore {
    my ( $class, $name ) = @_;

    my $sql = q|
    CREATE TABLE file (
        file text,
        processed int default 0
    );

    CREATE TABLE post (
        id integer primary key autoincrement,
        href not null unique,
        time text,
        hash text,
        description text,
        tag text,
        extended text,
        meta text
    );

    CREATE TABLE processed (
        href text primary key
    );

    CREATE TABLE response (
        id integer primary key autoincrement,
        href text,
        code integer,
        seconds1970 integer
    );

    |;

    my $tmp = "/tmp/init.sql";
    open(OUT, '>', $tmp) or die($!);
    print OUT $sql;
    close OUT;
    system("sqlite3 $name < $tmp");
    unlink $tmp;
}


=head2 check

Checks links for HTTP status.

=cut

sub check {
    my ( $class, $schema, $limit ) = @_;

    my @potential = $class->getUncheckedPotential($schema, $limit);

    my $agent = LWP::UserAgent->new;
    $agent->agent('Link Checker/0.10');
    $agent->from('jrowe@jrowe.org');
    $agent->max_redirect(0);
    $agent->timeout(5);

    print 'Checking ' . scalar(@potential) . ' posts.' . "\n";

    foreach ( @potential ) {
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


sub getUncheckedPotential {
    my ( $class, $schema, $limit ) = @_;

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

=head1 AUTHOR

Joshua T. Rowe, C<< <jrowe at jrowe.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-net-delicious-checker at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-Delicious-Checker>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::Delicious::Checker


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-Delicious-Checker>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-Delicious-Checker>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-Delicious-Checker>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-Delicious-Checker/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Joshua T. Rowe.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Net::Delicious::Checker
