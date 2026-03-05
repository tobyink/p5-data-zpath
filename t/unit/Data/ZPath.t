=pod

=encoding utf-8

=head1 PURPOSE

Unit tests for L<Data::ZPath>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2026 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.


=cut

use Test2::V0 -target => 'Data::ZPath';
use Test2::Tools::Spec;
use Data::Dumper;

describe "class `$CLASS`" => sub {

	tests 'method `new`' => sub {
	
		my $p = Data::ZPath->new('foo');
		ok( $p->isa('Data::ZPath'), 'constructed an object' );
	};
};

done_testing;
