use strict;
use warnings;

package Data::ZPath::_Lexer;

use Carp qw(croak);

our $VERSION = '0.001';

sub new {
    my ($class, $src) = @_;
    my $self = bless {
        src   => $src,
        i     => 0,
        toks  => [],
        pos   => 0,
    }, $class;

    $self->{toks} = $self->_tokenize($src);
    return $self;
}

sub peek_kind   { $_[0]->{toks}->[$_[0]->{pos}]->{k} }
sub peek_kind_n { $_[0]->{toks}->[$_[0]->{pos} + $_[1]]->{k} }

sub next_tok {
    my ($self) = @_;
    return $self->{toks}->[$self->{pos}++];
}

sub expect {
    my ($self, $k) = @_;
    my $t = $self->next_tok;
    croak "Expected $k, got $t->{k}" unless $t->{k} eq $k;
    return $t;
}

sub _is_ws {
    my ($c) = @_;
    return defined $c && $c =~ /\s/;
}

sub _tokenize {
    my ($self, $src) = @_;
    my @t;

    my @c = split //, $src;
    my $n = @c;

    my $i = 0;
    my $push = sub { push @t, @_ };

    while ($i < $n) {
        my $ch = $c[$i];

        if ($ch =~ /\s/) { $i++; next; }

        # path slash token (always a token, but distinct from division op)
        if ($ch eq '/') {
            $push->({ k => 'SLASH_PATH', v => '/' });
            $i++;
            next;
        }

        # single-char delimiters
        if ($ch eq '(') { $push->({ k => 'LPAREN', v => '(' }); $i++; next; }
        if ($ch eq ')') { $push->({ k => 'RPAREN', v => ')' }); $i++; next; }
        if ($ch eq '[') { $push->({ k => 'LBRACK', v => '[' }); $i++; next; }
        if ($ch eq ']') { $push->({ k => 'RBRACK', v => ']' }); $i++; next; }
        if ($ch eq ',') { $push->({ k => 'COMMA', v => ',' }); $i++; next; }

        # dot/dotdot variants (path segments)
        if ($ch eq '.') {
            if ($i + 2 < $n && $c[$i+1] eq '.' && $c[$i+2] eq '*') {
                $push->({ k => 'DOTDOTSTAR', v => '..*' });
                $i += 3;
                next;
            }
            if ($i + 1 < $n && $c[$i+1] eq '.') {
                $push->({ k => 'DOTDOT', v => '..' });
                $i += 2;
                next;
            }
            $push->({ k => 'DOT', v => '.' });
            $i++;
            next;
        }

        # star / starstar (path segments)
        if ($ch eq '*') {
            if ($i + 1 < $n && $c[$i+1] eq '*') {
                $push->({ k => 'STARSTAR', v => '**' });
                $i += 2;
                next;
            }
            $push->({ k => 'STAR_PATH', v => '*' });
            $i++;
            next;
        }

        # unary ops (no whitespace requirement)
        if ($ch eq '!') {
            # do not lex "!=" as binary unless whitespace-wrapped; still allow unary ! always
            # If it's "!=" with whitespace around, it will be lexed by binary section later.
            $push->({ k => 'NOT', v => '!' });
            $i++;
            next;
        }
        if ($ch eq '~') {
            $push->({ k => 'BNOT', v => '~' });
            $i++;
            next;
        }

        # ternary requires whitespace around ? and :
        if ($ch eq '?' || $ch eq ':') {
            my $prev = $i > 0 ? $c[$i-1] : undef;
            my $next = $i + 1 < $n ? $c[$i+1] : undef;
            if (_is_ws($prev) && _is_ws($next)) {
                $push->({ k => ($ch eq '?') ? 'QMARK' : 'COLON', v => $ch });
                $i++;
                next;
            }
            croak "Ternary operator '$ch' requires whitespace around it";
        }

        # string
        if ($ch eq '"') {
            $i++;
            my $s = '';
            my $esc = 0;
            while ($i < $n) {
                my $cc = $c[$i++];
                if ($esc) {
                    $s .= _unescape_char($cc);
                    $esc = 0;
                    next;
                }
                if ($cc eq '\\') { $esc = 1; next; }
                last if $cc eq '"';
                $s .= $cc;
            }
            $push->({ k => 'STRING', v => $s });
            next;
        }

        # index token: #digits (path segment)
        if ($ch eq '#') {
            my $j = $i + 1;
            croak "Invalid index '#'" unless $j < $n && $c[$j] =~ /\d/;
            my $num = '';
            while ($j < $n && $c[$j] =~ /\d/) { $num .= $c[$j++]; }
            $push->({ k => 'INDEX', v => 0 + $num });
            $i = $j;
            next;
        }

        # number
        if ($ch =~ /[0-9]/) {
            my $j = $i;
            my $num = '';
            while ($j < $n && $c[$j] =~ /[0-9.]/) { $num .= $c[$j++]; }
            $push->({ k => 'NUMBER', v => 0 + $num });
            $i = $j;
            next;
        }

        # binary operators: + - * / % && || ^ & | == != >= <= > <
        # require whitespace on both sides (per zpath.me)
        {
            my $prev = $i > 0 ? $c[$i-1] : undef;
            my $next = $i + 1 < $n ? $c[$i+1] : undef;

            my $ws_ok_1 = _is_ws($prev);
            # for 2-char ops, check next-next for ws too
            my $next2 = $i + 2 < $n ? $c[$i+2] : undef;

            if ($ws_ok_1) {
                # 2-char ops
                if ($ch eq '&' && defined $next && $next eq '&' && _is_ws($next2)) { $push->({ k => 'ANDAND', v => '&&' }); $i += 2; next; }
                if ($ch eq '|' && defined $next && $next eq '|' && _is_ws($next2)) { $push->({ k => 'OROR',  v => '||' }); $i += 2; next; }
                if ($ch eq '=' && defined $next && $next eq '=' && _is_ws($next2)) { $push->({ k => 'EQEQ',  v => '==' }); $i += 2; next; }
                if ($ch eq '!' && defined $next && $next eq '=' && _is_ws($next2)) { $push->({ k => 'NEQ',   v => '!=' }); $i += 2; next; }
                if ($ch eq '>' && defined $next && $next eq '=' && _is_ws($next2)) { $push->({ k => 'GE',    v => '>=' }); $i += 2; next; }
                if ($ch eq '<' && defined $next && $next eq '=' && _is_ws($next2)) { $push->({ k => 'LE',    v => '<=' }); $i += 2; next; }

                # 1-char ops
                if (_is_ws($next)) {
                    if ($ch eq '+') { $push->({ k => 'PLUS',  v => '+' }); $i++; next; }
                    if ($ch eq '-') { $push->({ k => 'MINUS', v => '-' }); $i++; next; }
                    if ($ch eq '*') { $push->({ k => 'STAR',  v => '*' }); $i++; next; }
                    if ($ch eq '%') { $push->({ k => 'PCT',   v => '%' }); $i++; next; }
                    if ($ch eq '^') { $push->({ k => 'BXOR',  v => '^' }); $i++; next; }
                    if ($ch eq '&') { $push->({ k => 'BAND',  v => '&' }); $i++; next; }
                    if ($ch eq '|') { $push->({ k => 'BOR',   v => '|' }); $i++; next; }
                    if ($ch eq '>') { $push->({ k => 'GT',    v => '>' }); $i++; next; }
                    if ($ch eq '<') { $push->({ k => 'LT',    v => '<' }); $i++; next; }
                    if ($ch eq '/') { $push->({ k => 'SLASH', v => '/' }); $i++; next; }
                }
            }
        }

        # NAME (path segment or function name), supports backslash-escaped chars in name
        my $name = _read_name(\@c, $i);
        if (defined $name->{v} && length $name->{v}) {
            $push->({ k => 'NAME', v => $name->{v} });
            $i = $name->{i};
            next;
        }

        croak "Unexpected character '$ch' at position $i";
    }

    push @t, { k => 'EOF', v => '' };
    return \@t;
}

sub _unescape_char {
    my ($c) = @_;
    return "\n" if $c eq 'n';
    return "\r" if $c eq 'r';
    return "\t" if $c eq 't';
    return $c;
}

sub _read_name {
    my ($chars, $i) = @_;
    my $n = @$chars;

    my %delim = map { $_ => 1 } split //, "\n\r\t()[]/,=&|!<># ";
    my $buf = '';
    my $esc = 0;

    my $start = $i;
    while ($i < $n) {
        my $c = $chars->[$i];

        if ($esc) {
            $buf .= $c;
            $esc = 0;
            $i++;
            next;
        }

        if ($c eq '\\') {
            $esc = 1;
            $i++;
            next;
        }

        last if $delim{$c};
        last if $c =~ /\s/;
        $buf .= $c;
        $i++;
    }

    return { v => '', i => $start } unless length $buf;
    return { v => $buf, i => $i };
}

1;
