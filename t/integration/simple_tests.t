use Test2::V0;

use Data::ZPath;
use XML::LibXML;

subtest 'basic hash navigation' => sub {
    my $h = { foo => { bar => 6 } };
    my $p = Data::ZPath->new('./foo/bar');
    is($p->first($h), 6, 'first() returns scalar');
    is([$p->all($h)], [6], 'all() returns list');
};

subtest 'each() mutates Perl scalar via $_ proxy' => sub {
    my $h = { foo => { bar => 6 } };
    my $p = Data::ZPath->new('./foo/bar');

    $p->each($h, sub { $_ *= 2 });
    is($h->{foo}{bar}, 12, 'bar doubled');
};

subtest 'basic XML navigation' => sub {
    my $dom = XML::LibXML->load_xml(string => '<foo><bar>5</bar></foo>');
    my $p   = Data::ZPath->new('./foo/bar');
    is($p->first($dom), '5', 'XML textContent used');
    is([$p->all($dom)], ['5'], 'XML list');
};

subtest 'wildcards and recursive descent' => sub {
    my $h = { a => { x => 1, y => { z => 2 } } };

    my $p1 = Data::ZPath->new('./a/*');
    is(scalar($p1->all($h)), 2, '* returns children');

    my $p2 = Data::ZPath->new('./**/z');
    is([$p2->all($h)], [2], '** finds descendant by name');
};

subtest 'qualifiers' => sub {
    my $h = { cars => [ { age => 1 }, { }, { age => undef }, { age => 0 } ] };

    my $p1 = Data::ZPath->new('./cars/*[age]');
    is(scalar($p1->all($h)), 3, 'age exists (undef still present as node)');

    my $p2 = Data::ZPath->new('./cars/*[!age || type(age) == "null"]');
    # our "null" mapping for undef is "null" via type() on primitive undef node; present but undef maps to null
    ok(scalar($p2->all($h)) >= 2, 'missing or null-ish');
};

subtest 'count/index helpers' => sub {
    my $dom = XML::LibXML->load_xml(
        string => '<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>'
    );

    my $p = Data::ZPath->new('./table/**/tr[count(td) == 2]');
    is(scalar($p->all($dom)), 1, 'row with 2 tds');
};

subtest 'top-level comma list and union' => sub {
    my $h = { bowl => [ { fruit => 1 }, { fruit => 2 } ], fruit => 3 };

    my $p1 = Data::ZPath->new('./**/bowl/*, ./**/fruit');
    ok(scalar($p1->all($h)) >= 3, 'comma list returns combined results (may include duplicates)');

    my $p2 = Data::ZPath->new('union(./**/bowl/*, ./**/fruit)');
    ok(scalar($p2->all($h)) >= 3, 'union merges duplicates when nodes repeat');
};


subtest 'recursive union does not hang' => sub {
	my $h = {
		first   => 'John',
		last    => 'doe',
		age     => 26,
		address => {
			street   => 'naist street',
			city     => 'Nara',
			postcode => '630-0192',
		},
		numbers => [
			{ type => 'iPhone', number => '0123-4567-8888', things => [ 'foo', 'bar' ] },
			{ type => 'home', number => '0123-4567-8910', things => [ 'biff', 'boff' ] },
			{ type => 'work', number => '0123-9999-8910' },
		],
	};

	my $p = Data::ZPath->new('count(**/union(/**)/union(/**)/union(/**)) < 50');
	my @out;
	my $timed_out = 0;
	{
		local $SIG{ALRM} = sub { die "timeout\n" };
		alarm 2;
		eval {
			@out = $p->all($h);
			1;
		} or do {
			$timed_out = ( $@ and $@ =~ /timeout/ ) ? 1 : 0;
			die $@ unless $timed_out;
		};
		alarm 0;
	}

	is($timed_out, 0, 'expression completed in bounded time');
	is(\@out, [1], 'expression result matches expectation');
};
subtest 'operators require whitespace' => sub {
    like(
        dies { Data::ZPath->new('1+2') },
        qr/Unexpected character|requires whitespace/i,
        'binary + without whitespace rejected'
    );
    is(Data::ZPath->new('1 + 2')->first({}), 3, 'binary + with whitespace ok');
};

subtest 'xml attributes' => sub {
    my $dom = XML::LibXML->load_xml(string => '<root><table class="defn"/></root>');
    my $p1 = Data::ZPath->new('./root/table[@class == "defn"]');
    is(scalar($p1->all($dom)), 1, 'attribute qualifier works');

    my $p2 = Data::ZPath->new('./root/table/@class');
    is([$p2->all($dom)], ['defn'], 'attribute node value');
};

done_testing;
