package Net::Delicious::Checker;

use warnings;
use strict;

use Compress::Bzip2;
use Config::Simple;
use Data::Dumper;
use File::Basename;
use File::Path qw( make_path );
use Log::Log4perl qw( :easy );
use LWP::UserAgent;
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

=cut

my $CONFIG_FILE = $ENV{'HOME'} . '/.deliciouscheckerrc';


=head1 SUBROUTINES/METHODS

=head2 new

Creates a new object.

=cut

sub new {
    my ( $class ) = @_;

    my $self = {
    };

    bless $self, $class;

    if ( -e $CONFIG_FILE ) {
        $self->{'config'} = Config::Simple->new($CONFIG_FILE);
    }
    else {
        $self->{'config'} = Config::Simple->new(syntax => 'ini');
        $self->{'config'}->param('username', '');
        $self->{'config'}->param('password', '');
        $self->{'config'}->param('email', '');
        $self->{'config'}->write($CONFIG_FILE);
    }

    return $self;
}


=head2 config

Returns the config object.

=cut

sub config {
    my ( $self ) = @_;

    return $self->{'config'};
}


=head2 fetch

Fetch all of the delicious bookmarks.

=cut

sub fetch {
    my ( $self ) = @_;

    my $url = 'https://api.del.icio.us/v1/posts/recent?count=10';

    my $agent = LWP::UserAgent->new();
    if ( my $email = $self->config->param('email') ) {
        $agent->from($email);
    }
    $agent->agent(ref($self) . ' ' . $VERSION);

    $agent->credentials(
            'api.del.icio.us:443',
            'del.icio.us API',
            $self->config->param('username'), $self->config->param('password'));

    my $response = $agent->get($url);

    INFO $response->status_line . "\n";

    if ( $response->is_success ) {
        my $dir = $self->config->param('dir');
        my $file = $dir . '/fetch.xml';

        make_path($dir);

        my $FH;
        open($FH, '>', $file)
                or die('Cannot write to "' . $file . '" : ' . $!);

        print $FH $response->decoded_content;
        INFO 'Wrote ' . $file . "\n";

        close $FH;

        $self->compressPrevious;
    }

    exit;
}


=head2 compressPrevious

Compress the previously downloaded XML files.

=cut

sub compressPrevious {
    my ( $self ) = @_;

    my $dir = $self->config->param('dir');

    my $DIR;
    opendir($DIR, $dir)
            or die('Cannot read directory "' . $dir . '" : ' . $!);

    foreach my $file ( grep { m/\.xml$/ } readdir $DIR ) {
        my $ffile = $dir . '/' . $file;

        INFO "Bzipping $ffile\n";

        my $IN;
        open($IN, '<', $ffile)
            or die('Cannot read to "' . $ffile . '" : ' . $!);
        my $content = join '', <$IN>;
        close $IN;

        my $ok = eval {
            my $bzFile = $ffile . '.bz2';
            my $bz = Compress::Bzip2->new;
            $bz->bzopen($bzFile, 'w');
            $bz->bzwrite($content);
            $bz->bzclose;

            1;
        };
        if ( ( ! $ok ) || $@ ) {
            ERROR "Error in bzipping " . $ffile . "\n";
        }
        else {
            unlink $ffile;
        }
    }

    closedir $DIR;

}


=head2 load

Loads a delicious.com XML file into the data store.

=cut

sub load {
    my ( $class, $schema, $file ) = @_;

    INFO 'Loading file ' . $file . "\n";

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
            ERROR 'ERROR: Error inserting post [ ' . $@ . ' ]' . "\n";
            ERROR 'post: ' . Dumper($args) . "\n";
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

    INFO 'Checking ' . scalar(@potential) . ' posts.' . "\n";

    foreach ( @potential ) {
        my $href = $_->href;
        my $response = $agent->head($href);
        my $code = $response->code;
        $schema->resultset('Response')->create({
            href        => $href,
            code        => $code,
            seconds1970 => time,
        });

        INFO $code . ' ' . $href . "\n";
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
