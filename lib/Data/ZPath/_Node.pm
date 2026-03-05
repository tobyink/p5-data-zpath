use strict;
use warnings;

package Data::ZPath::_Node;

use B ();
use Scalar::Util qw(blessed refaddr reftype isdual);

our $VERSION = '0.001';

sub _created_as_string {
    my $value = shift;
    defined $value
        and not ref $value
        and not _is_bool( $value )
        and not _created_as_number( $value );
}

sub _created_as_number {
    my $value = shift;
    return !!0 unless defined $value;
    return !!0 if ref $value;
    return !!0 if utf8::is_utf8( $value );
    my $b_obj = B::svref_2object(\$value);
    my $flags = $b_obj->FLAGS;
    return !!1 if $flags & ( B::SVp_IOK() | B::SVp_NOK() ) and not( $flags & B::SVp_POK() );
    return !!0;
}

sub _is_bool {
    my $value = shift;

    my $ref = ref($value) || '';
    if ($ref eq 'SCALAR' and defined $$value) {
        return !!1 if $$value eq 0;
        return !!1 if $$value eq 1;
    }

    return !!0 unless defined $value;
    return !!0 if $ref;
    return !!0 unless isdual( $value );
    return !!1 if  $value and "$value" eq '1' and $value + 0 == 1;
    return !!1 if not $value and "$value" eq q'' and $value + 0 == 0;
    return !!0;
}

sub from_root {
    my ($class, $obj) = @_;
    return $class->_wrap($obj, undef, undef);
}

sub _wrap {
    my ($class, $obj, $parent, $key) = @_;

    my $is_xml = blessed($obj) && $obj->isa('XML::LibXML::Node');
    my $id;

    if ($is_xml) {
        $id = 'xml:' . refaddr($obj);
    } elsif (ref($obj)) {
        $id = 'ref:' . refaddr($obj);
    } elsif ($parent) {
        my $pid = $parent->id;
        $pid = 'root' unless defined $pid;
        my $k = defined $key ? $key : '';
        $id = 'slot:' . $pid . ':' . $k;
    } else {
        # primitive: no stable identity, but used as a value node (not deduped as a tree node)
        $id = undef;
    }

    return bless {
        raw    => $obj,
        parent => $parent,
        key    => $key,
        id     => $id,
        slot   => undef, # coderef getter/setter for Perl scalar lvalue
    }, $class;
}

sub raw    { $_[0]->{raw} }
sub parent { $_[0]->{parent} }
sub key    { $_[0]->{key} }
sub id     { $_[0]->{id} }

sub slot {
    my ($self) = @_;
    return $self->{slot};
}

sub with_slot {
    my ($self, $slot) = @_;
    $self->{slot} = $slot;
    return $self;
}

sub type {
    my ($self) = @_;
    my $x = $self->{raw};

    if (blessed($x) && $x->isa('XML::LibXML::Namespace')) {
        return 'attr';
    }
    if (blessed($x) && $x->isa('XML::LibXML::Attr')) {
        return 'attr';
    }
    if (blessed($x) && $x->isa('XML::LibXML::Text')) {
        return 'text';
    }
    if (blessed($x) && $x->isa('XML::LibXML::Element')) {
        return 'element';
    }
    if (blessed($x) && $x->isa('XML::LibXML::Document')) {
        return 'document';
    }

    return 'null'    unless defined $x;
    return 'map'     if ref($x) eq 'HASH';
    return 'list'    if ref($x) eq 'ARRAY';
    return 'boolean' if _is_bool($x);
    return 'number'  if _created_as_number($x);
    return 'string'  if _created_as_string($x);
    return 'object';
}

sub primitive_value {
    my ($self) = @_;
    my $x = $self->{raw};

    if (blessed($x) && $x->isa('XML::LibXML::Document')) {
        my $de = $x->documentElement;
        return defined($de) ? $de->textContent : undef;
    }
    if (blessed($x) && $x->isa('XML::LibXML::Namespace')) {
        return $x->declaredURI // $x->nodeValue // '';
    }
    if (blessed($x) && $x->isa('XML::LibXML::Attr')) {
        return $x->getValue;
    }
    if (blessed($x) && $x->isa('XML::LibXML::Element')) {
        return $x->textContent;
    }
    if (blessed($x) && $x->isa('XML::LibXML::Text')) {
        return $x->data;
    }

    if ( ref $x and reftype($x) and reftype($x) eq 'SCALAR' ) {
        return !!$$x if $x eq 0 || $x eq 1;
    }

    return $x;
}

sub string_value {
    my ($self) = @_;
    my $v = $self->primitive_value;
    return undef unless defined $v;
    return "$v";
}

sub number_value {
    my ($self) = @_;
    my $v = $self->primitive_value;
    return undef unless defined $v && Scalar::Util::looks_like_number($v);
    return 0 + $v;
}

sub children {
    my ($self) = @_;
    my $x = $self->{raw};

    # XML document: treat documentElement as child
    if (blessed($x) && $x->isa('XML::LibXML::Document')) {
        my $de = $x->documentElement;
        return () unless $de;
        return (Data::ZPath::_Node->_wrap($de, $self, 0));
    }

    if (blessed($x) && $x->isa('XML::LibXML::Element')) {
        my @kids = $x->childNodes;
        return map { Data::ZPath::_Node->_wrap($_, $self, $_->nodeName) } @kids;
    }

    if (ref($x) eq 'HASH') {
        my @out;
        for my $k (keys %$x) {
            my $child = Data::ZPath::_Node->_wrap($x->{$k}, $self, $k);
            $child->with_slot(sub {
                if (@_) { $x->{$k} = $_[0]; }
                return $x->{$k};
            }) unless ref($x->{$k});
            push @out, $child;
        }
        return @out;
    }

    if (ref($x) eq 'ARRAY') {
        my @out;
        for (my $i = 0; $i < @$x; $i++) {
            my $child = Data::ZPath::_Node->_wrap($x->[$i], $self, $i);
            $child->with_slot(sub {
                if (@_) { $x->[$i] = $_[0]; }
                return $x->[$i];
            }) unless ref($x->[$i]);
            push @out, $child;
        }
        return @out;
    }

    return ();
}

sub attributes {
    my ($self) = @_;
    my $x = $self->{raw};
    return () unless blessed($x) && $x->isa('XML::LibXML::Element');
    my @attrs = $x->attributes;
    return map { Data::ZPath::_Node->_wrap($_, $self, '@' . $_->nodeName) } @attrs;
}

sub name {
    my ($self) = @_;
    my $x = $self->{raw};

    if (blessed($x) && $x->isa('XML::LibXML::Attr'))    { return '@' . $x->nodeName; }
    if (blessed($x) && $x->isa('XML::LibXML::Element')) { return $x->nodeName; }
    if (blessed($x) && $x->isa('XML::LibXML::Text'))    { return '#text'; }

    return $self->{key};
}

1;
