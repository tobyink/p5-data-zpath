use strict;
use warnings;

package Data::ZPath;

use Scalar::Util qw(blessed refaddr looks_like_number);
use POSIX qw(ceil floor);
use Carp qw(croak);

use Data::ZPath::_Ctx;
use Data::ZPath::_Lexer;
use Data::ZPath::_Node;
use Data::ZPath::_Parser;
use Data::ZPath::_ScalarProxy;

our $VERSION = '0.001';

our @CARP_NOT = qw(
    Data::ZPath::_Ctx
    Data::ZPath::_Lexer
    Data::ZPath::_Node
    Data::ZPath::_Parser
    Data::ZPath::_ScalarProxy
);

for my $pkg ( @CARP_NOT ) {
    no strict 'refs';
    *{"${pkg}::CARP_NOT"} = \@CARP_NOT;
}

sub new {
    my ($class, $expr) = @_;
    croak "Missing expression" unless defined $expr;

    my $self = bless {
        expr_src => $expr,
        terms    => Data::ZPath::_Parser::_parse_top_level_terms($expr),
    }, $class;

    return $self;
}

sub first {
    my ($self, $root) = @_;
    my @vals = $self->all($root);
    return $vals[0];
}

sub all {
    my ($self, $root) = @_;

    my $ctx = Data::ZPath::_Ctx->new($root);
    my @out;

    for my $term (@{$self->{terms}}) {
        my @res = _eval_expr($term, $ctx);
        push @out, map { _node_to_primitive($_) } @res;
    }

    return @out;
}

sub each {
    my ($self, $root, $cb) = @_;
    croak "each() requires a coderef" unless ref($cb) eq 'CODE';

    my $ctx = Data::ZPath::_Ctx->new($root);
    for my $term (@{$self->{terms}}) {
        my @res = _eval_expr($term, $ctx);

		for my $node (@res) {
			my $slot = $node->slot;
			croak "each() can only mutate Perl map/list scalars (not XML)" unless $slot && ref($slot) eq 'CODE';

			tie my $proxy, 'Data::ZPath::_ScalarProxy', $slot;
			for ($proxy) {
				$cb->();
			}
			untie $proxy;
		}
	}

    return;
}

sub _eval_expr {
    my ($ast, $ctx) = @_;

    my $t = $ast->{t};

    if ($t eq 'num') {
        return (Data::ZPath::_Node->_wrap($ast->{v}, undef, undef));
    }
    if ($t eq 'str') {
        return (Data::ZPath::_Node->_wrap($ast->{v}, undef, undef));
    }
    if ($t eq 'path') {
        return _eval_path($ast, $ctx);
    }
    if ($t eq 'fn') {
        return _eval_fn($ast, $ctx);
    }
    if ($t eq 'un') {
        my @v = _eval_expr($ast->{e}, $ctx);
        my $x = _truthy($v[0]);
        if ($ast->{op} eq '!') {
            return (Data::ZPath::_Node->_wrap($x ? 0 : 1, undef, undef));
        }
        if ($ast->{op} eq '~') {
            my $n = _to_number($v[0]);
            return () unless defined $n;
            return (Data::ZPath::_Node->_wrap((~(int($n))), undef, undef));
        }
        croak "Unknown unary op $ast->{op}";
    }
    if ($t eq 'bin') {
        my @l = _eval_expr($ast->{l}, $ctx);
        my @r = _eval_expr($ast->{r}, $ctx);

        my $lv = $l[0];
        my $rv = $r[0];
        my $op = $ast->{op};

        # Logical ops treat as booleans
        if ($op eq '&&' || $op eq '||') {
            my $lb = _truthy($lv);
            return (Data::ZPath::_Node->_wrap(
                ($op eq '&&') ? ($lb && _truthy($rv) ? 1 : 0) : ($lb || _truthy($rv) ? 1 : 0),
                undef, undef
            ));
        }

        # Equality (loose-ish, but stable)
        if ($op eq '==' || $op eq '!=') {
            my $eq = _equals($lv, $rv);
            $eq = !$eq if $op eq '!=';
            return (Data::ZPath::_Node->_wrap($eq ? 1 : 0, undef, undef));
        }

        # Relations (numeric if both numeric, else string)
        if ($op =~ /^(>=|<=|>|<)$/) {
            my $ln = _to_number($lv);
            my $rn = _to_number($rv);
            my $ok;
            if (defined $ln && defined $rn) {
                $ok = ($op eq '>=' ? $ln >= $rn
                    :  $op eq '<=' ? $ln <= $rn
                    :  $op eq '>'  ? $ln >  $rn
                    :               $ln <  $rn);
            } else {
                my $ls = _to_string($lv) // '';
                my $rs = _to_string($rv) // '';
                $ok = ($op eq '>=' ? $ls ge $rs
                    :  $op eq '<=' ? $ls le $rs
                    :  $op eq '>'  ? $ls gt $rs
                    :               $ls lt $rs);
            }
            return (Data::ZPath::_Node->_wrap($ok ? 1 : 0, undef, undef));
        }

        # Bitwise ops (ints)
        if ($op eq '&' || $op eq '|' || $op eq '^') {
            my $ln = _to_number($lv);
            my $rn = _to_number($rv);
            return () unless defined $ln && defined $rn;
            my $li = int($ln);
            my $ri = int($rn);
            my $res = ($op eq '&') ? ($li & $ri) : ($op eq '|') ? ($li | $ri) : ($li ^ $ri);
            return (Data::ZPath::_Node->_wrap($res, undef, undef));
        }

        # Arithmetic (scalar only)
        if ($op eq '+' || $op eq '-' || $op eq '*' || $op eq '/' || $op eq '%') {
            my $ln = _to_number($lv);
            my $rn = _to_number($rv);
            return () unless defined $ln && defined $rn;
            my $res =
                $op eq '+' ? ($ln + $rn) :
                $op eq '-' ? ($ln - $rn) :
                $op eq '*' ? ($ln * $rn) :
                $op eq '/' ? ($rn == 0 ? undef : ($ln / $rn)) :
                ($rn == 0 ? undef : ($ln % $rn));
            return () unless defined $res;
            return (Data::ZPath::_Node->_wrap($res, undef, undef));
        }

        croak "Unknown binary op $op";
    }
    if ($t eq 'ternary') {
        my @c = _eval_expr($ast->{c}, $ctx);
        my $cond = _truthy($c[0]);
        return $cond ? _eval_expr($ast->{a}, $ctx) : _eval_expr($ast->{b}, $ctx);
    }

    croak "Unknown AST node type: $t";
}

sub _eval_path {
    my ($path_ast, $ctx) = @_;

    my @current = @{$ctx->nodeset};
    my $parentset = $ctx->parentset;

    for my $seg (@{$path_ast->{s}}) {
        my @next;

        if ($seg->{k} eq 'root') {
            @next = ($ctx->root);
        }
        elsif ($seg->{k} eq 'dot') {
            @next = @current;
        }
        elsif ($seg->{k} eq 'parent') {
            @next = grep { defined $_ } map { $_->parent } @current;
            @next = _dedup_nodes(@next);
        }
        elsif ($seg->{k} eq 'ancestors') {
            my @anc;
            for my $n (@current) {
                my $p = $n->parent;
                while ($p) {
                    push @anc, $p;
                    $p = $p->parent;
                }
            }
            @next = _dedup_nodes(@anc);
        }
        elsif ($seg->{k} eq 'star') {
            my @kids;
            for my $n (@current) {
                push @kids, grep { $_->type ne 'attr' } $n->children;
            }
            @next = _dedup_nodes(@kids);
        }
        elsif ($seg->{k} eq 'desc') {
            my @acc;
            my @stack = @current;
            while (@stack) {
                my $n = shift @stack;
                push @acc, $n;
                my @kids = grep { $_->type ne 'attr' } $n->children;
                push @stack, @kids;
            }
            @next = _dedup_nodes(@acc);
        }
        elsif ($seg->{k} eq 'index') {
            my $idx = $seg->{i};
            my @kids;
            for my $n (@current) {
                my @ch = grep { $_->type ne 'attr' } $n->children;
                push @kids, $ch[$idx] if defined $ch[$idx];
            }
            @next = _dedup_nodes(@kids);
        }
        elsif ($seg->{k} eq 'fnseg') {
            my @out;
            for my $n (@current) {
                my $seg_ctx = $ctx->with_nodeset([$n], \\@current);
                my @res = _eval_fn({ t => 'fn', n => $seg->{n}, a => $seg->{a} }, $seg_ctx);
                push @out, @res;
            }
            @next = @out;
        }
        elsif ($seg->{k} eq 'name') {
            my $name = $seg->{n};

            # XML attribute shorthand: @name or @*
            if ($name =~ /^\@/) {
                if ($name eq '@*') {
                    my @attrs;
                    for my $n (@current) { push @attrs, $n->attributes; }
                    @next = _dedup_nodes(@attrs);
                } else {
                    my $attr_name = substr($name, 1);
                    my @attrs;
                    for my $n (@current) {
                        my $raw = $n->raw;
                        next unless blessed($raw) && $raw->isa('XML::LibXML::Element');
                        my $a = $raw->getAttributeNode($attr_name);
                        push @attrs, Data::ZPath::_Node->_wrap($a, $n, '@'.$attr_name) if $a;
                    }
                    @next = _dedup_nodes(@attrs);
                }
            } else {
                my @kids;
                for my $n (@current) {
                    my @ch = grep { $_->type ne 'attr' } $n->children;
                    push @kids, grep { (defined($_->name) && $_->name eq $name) } @ch;
                }
                @next = _dedup_nodes(@kids);
            }

            if (defined $seg->{i}) {
                my $idx = $seg->{i};
                # interpret as: among matching name children for each parent, pick #idx
                my @picked;
                for my $n (@current) {
                    my @ch = grep { $_->type ne 'attr' } $n->children;
                    my @m  = grep { (defined($_->name) && $_->name eq $name) } @ch;
                    push @picked, $m[$idx] if defined $m[$idx];
                }
                @next = _dedup_nodes(@picked);
            }
        }
        else {
            croak "Unknown path segment kind: $seg->{k}";
        }

        # qualifiers
        if ($seg->{q} && @{$seg->{q}}) {
            my @filtered;
            for (my $i = 0; $i < @next; $i++) {
                my $node = $next[$i];
                my $ns_ctx = $ctx->with_nodeset(\@next, \@current);

                my $ok = 1;
                for my $q (@{$seg->{q}}) {
                    my @r = _eval_expr($q, $ns_ctx->with_nodeset([$node], \@next));
                    $ok &&= _truthy($r[0]);
                    last unless $ok;
                }
                push @filtered, $node if $ok;
            }
            @next = @filtered;
        }

        $parentset = \@current;
        @current = @next;
    }

    return @current;
}

sub _eval_fn {
    my ($fn_ast, $ctx) = @_;
    my $name = $fn_ast->{n};
    my @args = @{$fn_ast->{a}};

    my $ns = $ctx->nodeset;

    # helpers
    my $eval_arg = sub {
        my ($i, $local_ctx) = @_;
        return _eval_expr($args[$i], $local_ctx // $ctx);
    };

    if ($name eq 'count') {
        if (@args) {
            my @r = $eval_arg->(0);
            return (Data::ZPath::_Node->_wrap(scalar(@r), undef, undef));
        }
        my $scope = $ctx->parentset // $ns;
        return (Data::ZPath::_Node->_wrap(scalar(@$scope), undef, undef));
    }

    if ($name eq 'index') {
        if (@args) {
            # index(expression): for each node matched, its index into its parent
            my @r = $eval_arg->(0);
            my @out;
            for my $n (@r) {
                my $k = $n->key;
                push @out, Data::ZPath::_Node->_wrap((defined($k) && $k =~ /^\d+$/) ? 0+$k : undef, undef, undef)
                    if defined($k) && $k =~ /^\d+$/;
            }
            return @out;
        }

        # index() within qualifier scope: index of THIS node in parentset; otherwise nodeset
        my $cur = $ns->[0];
        return () unless $cur;

        my $scope = $ctx->parentset // $ns;
        my $id = $cur->id;
        return () unless defined $id;
        for (my $i = 0; $i < @$scope; $i++) {
            my $nid = $scope->[$i]->id;
            if (defined $nid && $nid eq $id) {
                return (Data::ZPath::_Node->_wrap($i, undef, undef));
            }
        }
        return (Data::ZPath::_Node->_wrap(0, undef, undef));
    }

    if ($name eq 'key') {
        if (@args) {
            my @r = $eval_arg->(0);
            return map {
                my $k = $_->key;
                defined $k ? Data::ZPath::_Node->_wrap($k, undef, undef) : ()
            } @r;
        }
        my $cur = $ns->[0];
        return () unless $cur && defined $cur->key;
        return (Data::ZPath::_Node->_wrap($cur->key, undef, undef));
    }

    if ($name eq 'union') {
        my @all;
        for my $i (0 .. $#args) {
            push @all, $eval_arg->($i);
        }
        return _dedup_nodes(@all);
    }

    if ($name eq 'intersection') {
        return () unless @args;
        my @base = $eval_arg->(0);
        my %have = map { $_->id // ("p:".refaddr(\$_)) => $_ } @base;

        for my $i (1 .. $#args) {
            my @r = $eval_arg->($i);
            my %next = map { $_->id // ("p:".refaddr(\$_)) => 1 } @r;
            for my $k (keys %have) {
                delete $have{$k} unless $next{$k};
            }
        }
        return values %have;
    }

    if ($name eq 'is-first') {
        my @i = _eval_fn({ t=>'fn', n=>'index', a=>[] }, $ctx);
        return () unless @i;
        return (Data::ZPath::_Node->_wrap($i[0]->primitive_value == 0 ? 1 : 0, undef, undef));
    }

    if ($name eq 'is-last') {
        my @i = _eval_fn({ t=>'fn', n=>'index', a=>[] }, $ctx);
        my @c = _eval_fn({ t=>'fn', n=>'count', a=>[] }, $ctx);
        return () unless @i && @c;
        return (Data::ZPath::_Node->_wrap($i[0]->primitive_value == ($c[0]->primitive_value - 1) ? 1 : 0, undef, undef));
    }

    if ($name eq 'next' || $name eq 'prev') {
        my $cur = $ns->[0];
        return () unless $cur && $cur->parent;
        my $praw = $cur->parent->raw;
        my $k = $cur->key;

        if (ref($praw) eq 'ARRAY' && defined $k && $k =~ /^\d+$/) {
            my $ni = $name eq 'next' ? $k + 1 : $k - 1;
            return () if $ni < 0 || $ni >= @$praw;
            my $child = Data::ZPath::_Node->_wrap($praw->[$ni], $cur->parent, $ni);
            $child->with_slot(sub { if (@_) { $praw->[$ni] = $_[0] } return $praw->[$ni] }) unless ref($praw->[$ni]);
            return ($child);
        }
        return ();
    }

    if ($name eq 'string') {
        if (@args) {
            my @r = $eval_arg->(0);
            return map {
                my $s = $_->string_value;
                defined $s ? Data::ZPath::_Node->_wrap($s, undef, undef) : ()
            } @r;
        }
        my $cur = $ns->[0];
        return () unless $cur;
        my $s = $cur->string_value;
        return defined $s ? (Data::ZPath::_Node->_wrap($s, undef, undef)) : ();
    }

    if ($name eq 'number') {
        if (@args) {
            my @r = $eval_arg->(0);
            return map {
                my $n = $_->number_value;
                defined $n ? Data::ZPath::_Node->_wrap($n, undef, undef) : ()
            } @r;
        }
        my $cur = $ns->[0];
        return () unless $cur;
        my $n = $cur->number_value;
        return defined $n ? (Data::ZPath::_Node->_wrap($n, undef, undef)) : ();
    }

    if ($name eq 'value') {
        if (@args) {
            my @r = $eval_arg->(0);
            return map {
                my $v = $_->primitive_value;
                defined $v ? Data::ZPath::_Node->_wrap($v, undef, undef) : Data::ZPath::_Node->_wrap(undef, undef, undef)
            } @r;
        }
        my $cur = $ns->[0];
        return () unless $cur;
        return (Data::ZPath::_Node->_wrap($cur->primitive_value, undef, undef));
    }

    if ($name eq 'type') {
        if (@args) {
            my @r = $eval_arg->(0);
            return ( Data::ZPath::_Node->_wrap('undefined', undef, undef) ) unless @r;
            return map {
                Data::ZPath::_Node->_wrap($_->type, undef, undef)
            } @r;
        }
        my $cur = $ns->[0];
        return (Data::ZPath::_Node->_wrap($cur ? $cur->type : 'undefined', undef, undef));
    }

    # Math helpers: map numeric over input set
    my $num_input = sub {
        my ($expr_idx) = @_;
        my @in = @args ? $eval_arg->($expr_idx) : @$ns;
        return map { $_->number_value } @in;
    };

    if ($name eq 'ceil' || $name eq 'floor' || $name eq 'round') {
        my @in = $num_input->(0);
        my @out;
        for my $x (@in) {
            next unless defined $x;
            my $v = $name eq 'ceil'  ? POSIX::ceil($x)
                  : $name eq 'floor' ? POSIX::floor($x)
                  :                    int($x + ($x >= 0 ? 0.5 : -0.5));
            push @out, Data::ZPath::_Node->_wrap($v, undef, undef);
        }
        return @out;
    }

    if ($name eq 'sum' || $name eq 'min' || $name eq 'max') {
        my @in;
        if (@args) {
            for my $i ( 0 .. $#args ) {
                push @in, $num_input->($i);
            }
        } else {
            @in = $num_input->(0);
        }

        @in = grep { defined } @in;
        return () unless @in;

        if ($name eq 'sum') {
            my $s = 0;
            $s += $_ for @in;
            return (Data::ZPath::_Node->_wrap($s, undef, undef));
        }
        if ($name eq 'min') {
            my $m = $in[0];
            ( $_ < $m ) and ( $m = $_ ) for @in;
            return (Data::ZPath::_Node->_wrap($m, undef, undef));
        }
        my $m = $in[0];
        ( $_ > $m ) and ( $m = $_ ) for @in;
        return (Data::ZPath::_Node->_wrap($m, undef, undef));
    }

    # String helpers
    my $str_input = sub {
        my ($expr_idx) = @_;
        my @in = @args ? $eval_arg->($expr_idx) : @$ns;
        return map { $_->string_value } @in;
    };

    if ($name eq 'escape') {
        my @in;
        if (@args) {
            for my $i (0..$#args) { push @in, $eval_arg->($i); }
        } else {
            @in = @$ns;
        }
        return map {
            my $s = $_->string_value // '';
            $s =~ s/&/&amp;/g;
            $s =~ s/</&lt;/g;
            $s =~ s/>/&gt;/g;
            $s =~ s/"/&quot;/g;
            $s =~ s/'/&apos;/g;
            Data::ZPath::_Node->_wrap($s, undef, undef)
        } @in;
    }

    if ($name eq 'unescape') {
        my @in;
        if (@args) {
            for my $i (0..$#args) { push @in, $eval_arg->($i); }
        } else {
            @in = @$ns;
        }
        return map {
            my $s = $_->string_value // '';
            $s =~ s/&lt;/</g;
            $s =~ s/&gt;/>/g;
            $s =~ s/&quot;/"/g;
            $s =~ s/&apos;/'/g;
            $s =~ s/&amp;/&/g;
            Data::ZPath::_Node->_wrap($s, undef, undef)
        } @in;
    }

    if ($name eq 'literal') {
        # ZTemplate-specific behavior; for Data::ZPath, it's a no-op passthrough
        my @in;
        if (@args) {
            for my $i (0..$#args) { push @in, $eval_arg->($i); }
        } else {
            @in = @$ns;
        }
        return @in;
    }

    if ($name eq 'format') {
        croak "format(format, expression)" unless @args >= 2;
        my @fmt = $eval_arg->(0);
        my $f = $fmt[0] ? ($fmt[0]->string_value // '') : '';
        my @in = $eval_arg->(1);
        return map {
            my $v = $_->primitive_value;
            Data::ZPath::_Node->_wrap(sprintf($f, $v), undef, undef)
        } @in;
    }

    if ($name eq 'index-of' || $name eq 'last-index-of') {
        croak "$name(expression, search)" unless @args >= 2;
        my @in = $eval_arg->(0);
        my $search = ($eval_arg->(1))[0]->string_value // '';
        return map {
            my $s = $_->string_value // '';
            my $pos = $name eq 'index-of' ? index($s, $search) : rindex($s, $search);
            Data::ZPath::_Node->_wrap($pos, undef, undef)
        } @in;
    }

    if ($name eq 'string-length') {
        my @in = @args ? $eval_arg->(0) : @$ns;
        return map {
            my $s = $_->string_value // '';
            Data::ZPath::_Node->_wrap(length($s), undef, undef)
        } @in;
    }

    if ($name eq 'upper-case' || $name eq 'lower-case') {
        my @in = @args ? $eval_arg->(0) : @$ns;
        return map {
            my $s = $_->string_value // '';
            $s = $name eq 'upper-case' ? uc($s) : lc($s);
            Data::ZPath::_Node->_wrap($s, undef, undef)
        } @in;
    }

    if ($name eq 'substring') {
        croak "substring(expression, start, length)" unless @args >= 3;
        my @in = $eval_arg->(0);
        my $start = ($eval_arg->(1))[0]->number_value // 0;
        my $len   = ($eval_arg->(2))[0]->number_value // 0;
        return map {
            my $s = $_->string_value // '';
            Data::ZPath::_Node->_wrap(substr($s, int($start), int($len)), undef, undef)
        } @in;
    }

    if ($name eq 'match' || $name eq 'matches') {
        croak "match(pattern, expression)" unless @args >= 2;
        my $pat = ($eval_arg->(0))[0]->string_value // '';
        my $re = eval { qr/$pat/ };
        croak "Invalid regex: $@" if $@;

        my @in = $eval_arg->(1);
        return map {
            my $s = $_->string_value // '';
            Data::ZPath::_Node->_wrap(($s =~ $re) ? 1 : 0, undef, undef)
        } @in;
    }

    if ($name eq 'replace') {
        croak "replace(pattern, replace, expression)" unless @args >= 3;
        my $pat = ($eval_arg->(0))[0]->string_value // '';
        my $rep = ($eval_arg->(1))[0]->string_value // '';
        my $re = eval { qr/$pat/ };
        croak "Invalid regex: $@" if $@;

        my @in = $eval_arg->(2);
        return map {
            my $s = $_->string_value // '';
            $s =~ s/$re/$rep/g;
            Data::ZPath::_Node->_wrap($s, undef, undef)
        } @in;
    }

    if ($name eq 'join') {
        croak "join(joiner, expression)" unless @args >= 2;
        my $joiner = ($eval_arg->(0))[0]->string_value // '';
        my @in = $eval_arg->(1);
        my @ss = map { $_->string_value // '' } @in;
        return (Data::ZPath::_Node->_wrap(join($joiner, @ss), undef, undef));
    }

    # XML functions
    if ($name eq 'url') {
        my @in = @args ? $eval_arg->(0) : @$ns;
        return map {
            my $raw = $_->raw;
            my $u = '';
            if (blessed($raw) && $raw->can('namespaceURI')) {
                $u = $raw->namespaceURI // '';
            }
            Data::ZPath::_Node->_wrap($u, undef, undef)
        } @in;
    }

    if ($name eq 'local-name') {
        my @in = @args ? $eval_arg->(0) : @$ns;
        return map {
            my $raw = $_->raw;
            my $ln = '';
            if (blessed($raw) && $raw->can('localname')) {
                $ln = $raw->localname // ($raw->nodeName // '');
            } else {
                $ln = $_->name // '';
            }
            Data::ZPath::_Node->_wrap($ln, undef, undef)
        } @in;
    }

    # CBOR tag() (optional marker), returns empty set if absent
    if ($name eq 'tag') {
        my @in = @args ? $eval_arg->(0) : @$ns;
        my @out;
        for my $n (@in) {
            my $raw = $n->raw;
            if (ref($raw) eq 'HASH' && exists $raw->{__zpath_tag}) {
                push @out, Data::ZPath::_Node->_wrap($raw->{__zpath_tag}, undef, undef);
            }
        }
        return @out;
    }

    croak "Unknown function '$name'";
}

sub _dedup_nodes {
    my @nodes = @_;
    my %seen;
    my @out;
    for my $n (@nodes) {
        my $id = $n->id;

        my $pv = $n->primitive_value;
        if ( defined $pv and not ref $pv ) {
            my $k = 'pv:' . $pv;
            next if $seen{$k}++;
            push @out, $n;
            next;
        }

        if ( not defined $id ) {
            my $k = 'pv:__NULL__';
            next if $seen{$k}++;
            push @out, $n;
            next;
        }

        next if $seen{$id}++;
        push @out, $n;
    }
    return @out;
}

sub _node_to_primitive {
    my ($n) = @_;
    return undef unless defined $n;
    return $n->primitive_value;
}

sub _truthy {
	my ($n) = @_;
	return 0 unless $n;

	# Path-selected nodes are truthy by existence.
	my $id = $n->id;
	return 1 if defined $id;

	my $v = $n->primitive_value;

    return 0 if !defined $v;
    return 0 if $v eq '' && !ref($v);
    return 0 if !ref($v) && ($v eq '0' || lc($v) eq 'false' || lc($v) eq 'null');
    return 1;
}

sub _to_number {
    my ($n) = @_;
    return undef unless $n;
    return $n->number_value;
}

sub _to_string {
    my ($n) = @_;
    return undef unless $n;
    return $n->string_value;
}

sub _equals {
    my ($a, $b) = @_;
    return 0 unless $a && $b;

    my $av = $a->primitive_value;
    my $bv = $b->primitive_value;

    return 1 if !defined($av) && !defined($bv);
    return 0 if !defined($av) || !defined($bv);

    if (!ref($av) && !ref($bv) && looks_like_number($av) && looks_like_number($bv)) {
        return (0 + $av) == (0 + $bv);
    }
    return "$av" eq "$bv";
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Data::ZPath - ZPath implementation for Perl

=pod

=head1 NAME

Data::ZPath - ZPath implementation for Perl

=head1 SYNOPSIS

  use Data::ZPath;
  use XML::LibXML;

  my $path = Data::ZPath->new('./foo/bar');
  my $dom  = XML::LibXML->load_xml( string => '<foo><bar>5</bar></foo>' );

  my $result  = $path->first($dom);      # 5
  my @results = $path->all($dom);        # ( 5 )

  my $hashref = { foo => { bar => 6 } };
  my $result2 = $path->first($hashref);  # 6

  $path->each($hashref, sub { $_ *= 2 }); # increments bar -> 12

=head1 DESCRIPTION

Implements the ZPath grammar and core functions described at https://zpath.me.

Key parsing rules from zpath.me:

=over

=item *

Paths are UNIX-like segments separated by "/".

=item *

Segments can be: "*", "**", ".", "..", "..*", a name, "#n", "name#n", a function call, and any segment can have qualifiers "[expr]" (zero or more).

=item *

Binary operators require whitespace on both sides.

=item *

Ternary "? :" requires whitespace around "?" and ":".

=item *

Top-level expression may be a comma-separated list of expressions.

=back

=head1 METHODS

=head2 new($expr)

Compile a ZPath expression.

=head2 first($root)

Evaluate and return the first primitive value.

=head2 all($root)

Evaluate and return all primitive values.

=head2 each($root, $callback)

Evaluate and invoke callback for each matched Perl scalar, aliasing C<$_> so modifications write back.

=cut

=head1 BUGS

Please report any bugs to
L<https://github.com/tobyink/p5-data-zpath/issues>.

=head1 SEE ALSO

L<https://zpath.me>.

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
