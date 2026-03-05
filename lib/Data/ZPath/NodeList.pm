use strict;
use warnings;

package Data::ZPath::NodeList;

use Scalar::Util qw(blessed);

our $VERSION = '0.001';

sub new {
	my ( $class, @nodes ) = @_;
	return bless \@nodes, $class;
}

sub _new_or_list {
	my ( $class, @nodes ) = @_;
	wantarray ? @nodes : $class->new( @nodes );
}

sub all {
	my ( $self ) = @_;
	return @$self;
}

sub values {
	my ( $self ) = @_;
	return map $_->value, @$self;
}

sub first {
	my ( $self ) = @_;
	return $self->[0];
}

sub last {
	my ( $self ) = @_;
	return $self->[-1];
}

sub find {
	require Data::ZPath;
	my ( $self, $zpath ) = @_;
	$zpath = Data::ZPath->new( $zpath ) unless blessed($zpath);

	return ref($self)->_new_or_list( map $_->find($zpath), $self->all );
}

sub grep {
	my ( $self, $cb ) = @_;
	ref($self)->_new_or_list( grep {
		my $node = $_;
		local $_ = $node->value;
		$cb->();
	} $self->all );
}

sub map {
	my ( $self, $cb ) = @_;
	ref($self)->_new_or_list( map {
		my $node = $_;
		local $_ = $node->value;
		map {
			my $new = $_;
			blessed($new) && $new->isa('Data::ZPath::NodeList') ? $new->all :
			blessed($new) && $new->isa('Data::ZPath::Node') ? $new :
			Data::ZPath::Node->from_root( $new )
		} $cb->();
	} $self->all );
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

=head2 C<< find( $zpath ) >>

Calls C<find> on all nodes in the list and returns the list of results.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2026 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
