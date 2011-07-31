package Net::Delicious::Checker::Schema;

use warnings;
use strict;

=head1 NAME

Net::Delicious::Checker::Schema - A DBIx::Class schema.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

The DBIx::Class schema for Net::Delicious::Checker.

This is not meant to be used directly by the user.

=cut

use base qw( DBIx::Class::Schema::Loader );

__PACKAGE__->use_namespaces(1);
__PACKAGE__->naming('v7');

__PACKAGE__->loader_options(
#    debug => 1
);


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
