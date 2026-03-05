use strict;
use warnings;

package Data::ZPath::NodeList;

our $VERSION = '0.001';

sub new {
	my ( $class, @nodes ) = @_;
	return bless \@nodes, $class;
}

sub all {
	my ( $self ) = @_;
	return @$self;
}

sub first {
	my ( $self ) = @_;
	return $self->[0];
}

sub last {
	my ( $self ) = @_;
	return $self->[-1];
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Data::ZPath::NodeList - list wrapper for Data::ZPath nodes

=head1 SYNOPSIS

  my $path = Data::ZPath->new('/foo/bar');
  my $list = $path->evaluate($root);

  my @nodes = $list->all;
  my $first = $list->first;
  my $last  = $list->last;

=head1 DESCRIPTION

Objects of this class contain a list of
L<Data::ZPath::Node> objects.

=head1 METHODS

=head2 C<< all >>

Returns all nodes as a list.

=head2 C<< first >>

Returns the first node, or C<undef>.

=head2 C<< last >>

Returns the last node, or C<undef>.

=cut
