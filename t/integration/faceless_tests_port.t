use Test2::V0;

use Data::ZPath;
use JSON::PP qw(decode_json);
use Scalar::Util qw(looks_like_number);
use XML::LibXML;

my $tests_file = 't/integration/data/tests.txt';
ok( -f $tests_file, 'upstream tests.txt exists in repository' ) or BAIL_OUT( 'missing tests file' );

open my $fh, '<', $tests_file or die "Unable to read $tests_file: $!";
my @lines = <$fh>;
close $fh;

my %roots;
my $mode;
my $current_case_mode;
my $buffer = '';
my @cases;

for my $idx ( 0 .. $#lines ) {
    my $line = $lines[$idx];
    chomp $line;

    if ( $line =~ /^---- BEGIN\s+(\w+)/ ) {
        $mode = uc $1;
        $current_case_mode = $mode;
        $buffer = '';
        next;
    }

    if ( defined $mode and $line =~ /^---- END/ ) {
        if ( $mode eq 'JSON' ) {
            $roots{JSON} = decode_json( $buffer );
        }
        elsif ( $mode eq 'XML' ) {
            $roots{XML} = XML::LibXML->load_xml( string => $buffer );
        }
        elsif ( $mode eq 'CBOR' ) {
            $roots{CBOR_RAW} = $buffer;
            $roots{CBOR} = {
                tagged    => { __zpath_tag => 123, value => 'John' },
                1         => 5,
            };
        }
        $mode = undef;
        next;
    }

    if ( defined $mode ) {
        $buffer .= "$line\n";
        next;
    }

    next if $line =~ /^\s*$/;
    next if $line =~ /^\s*#/;

    my ( $expr, $expect ) = split /\t+/, $line, 2;
    next unless defined $expr and defined $expect;

    $expr =~ s/^\s+|\s+$//g;
    $expect =~ s/\s+#.*$//;
    $expect =~ s/^\s+|\s+$//g;

    next unless length $expr;
    next unless length $expect;

    push @cases, {
        line    => $idx + 1,
        mode    => $current_case_mode,
        expr    => $expr,
        expect    => $expect,
    };
}

ok( scalar( @cases ) > 0, 'parsed cases from tests.txt' );

for my $case ( @cases ) {
    my $label = sprintf '[%s:%d] %s => %s',
        $case->{mode},
        $case->{line},
        $case->{expr},
        $case->{expect};

    subtest $label => sub {
        if ( $case->{mode} eq 'CBOR' ) {
            note 'CBOR fixture is stored unmodified from upstream tests.txt and approximated as Perl data for execution.';
        }

        if ( $case->{expect} eq 'ERROR' ) {
            like(
                dies { _run_expr( $case, \%roots ) },
                qr/.+/,
                'expression throws error'
            );
            return;
        }

        my @expected = $case->{expect} =~ m{^/}
            ? _run_expr( $case, \%roots, 'expect' )
            : _parse_expected_tokens( $case->{expect} );

        my @actual = _run_expr( $case, \%roots );

        is( [ sort @actual ], [ sort @expected ], 'result tokens match upstream expectation' );
    };
}

done_testing;

sub _run_expr {
    my ( $case, $roots, $key ) = @_;
    $key ||= 'expr';
    my $root = $roots->{ $case->{mode} };
    my $path = Data::ZPath->new( $case->{$key} );
    my @raw = $path->all( $root );
    return map { _stringify_actual_token( $_ ) } @raw;
}

sub _parse_expected_tokens {
    my ( $expect ) = @_;
    return () if $expect eq 'NULL';

    my @tokens;
    my $buf = '';
    my $in_quote = 0;

    for my $ch ( split //, $expect ) {
        if ( $ch eq '"' ) {
            $in_quote = $in_quote ? 0 : 1;
            $buf .= $ch;
            next;
        }

        if ( $ch eq ',' and not $in_quote ) {
            push @tokens, _stringify_expected_token( $buf );
            $buf = '';
            next;
        }

        $buf .= $ch;
    }

    push @tokens, _stringify_expected_token( $buf ) if length $buf;

    return @tokens;
}

sub _stringify_expected_token {
    my ( $tok ) = @_;
    $tok =~ s/^\s+|\s+$//g;

    if ( $tok =~ /^"(.*)"$/s ) {
        my $s = $1;
        $s =~ s/\\"/"/g;
        return $s;
    }

    return '__NULL__' if $tok eq 'null';
    return '1' if $tok eq 'true';
    return '0' if $tok eq 'false';
    return 0 + $tok if $tok =~ /^-?(?:\d+(?:\.\d+)?|\.\d+)$/;
    return $tok;
}

sub _stringify_actual_token {
    my ( $tok ) = @_;
    return '__NULL__' unless defined $tok;

    if ( not ref $tok and looks_like_number( $tok ) ) {
        return 0 + $tok;
    }

    return "$tok";
}
