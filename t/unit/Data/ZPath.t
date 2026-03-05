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

describe "class `$CLASS`" => sub {

	tests 'method `new`' => sub {
	
		my $p = Data::ZPath->new('foo');
		ok( $p->isa('Data::ZPath'), 'constructed an object' );
	};

	tests 'method `evaluate` (context behavior)' => sub {

		my $p = Data::ZPath->new('foo,bar');
		my $root = {
			foo => 1,
			bar => 2,
		};

		my @list_ctx = $p->evaluate($root);
		is( scalar @list_ctx, 2, 'returns list of nodes in list context' );
		ok( $list_ctx[0]->isa('Data::ZPath::Node'),
			'list context elements are nodes' );

		my $scalar_ctx = $p->evaluate($root);
		ok( $scalar_ctx->isa('Data::ZPath::NodeList'),
			'returns node list object in scalar context' );
		is( [ map $_->value, $scalar_ctx->all ], [ 1, 2 ],
			'scalar context node list wraps all nodes' );
	};
};

done_testing;
