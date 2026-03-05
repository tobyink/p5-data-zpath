=pod

=encoding utf-8

=head1 PURPOSE

Unit tests for L<Data::ZPath::NodeList>.

=cut

use Test2::V0 -target => 'Data::ZPath::NodeList';
use Test2::Tools::Spec;

use Data::ZPath::Node;

describe "class `$CLASS`" => sub {

	tests 'methods `all`, `first`, and `last`' => sub {

		my $node1 = Data::ZPath::Node->from_root('a');
		my $node2 = Data::ZPath::Node->from_root('b');
		my $node3 = Data::ZPath::Node->from_root('c');
		my $list = Data::ZPath::NodeList->new(
			$node1,
			$node2,
			$node3,
		);

		is( [ $list->all ], [ $node1, $node2, $node3 ],
			'all returns every node' );
		is( $list->first, $node1, 'first returns first node' );
		is( $list->last, $node3, 'last returns last node' );
	};

	tests 'first and last on empty lists' => sub {

		my $list = Data::ZPath::NodeList->new;

		is( [ $list->all ], [], 'all returns empty list' );
		is( $list->first, U(), 'first returns undef for empty list' );
		is( $list->last, U(), 'last returns undef for empty list' );
	};
};

done_testing;
