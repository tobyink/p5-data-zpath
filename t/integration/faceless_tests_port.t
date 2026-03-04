use Test2::V0;

use Data::ZPath;
use JSON::PP qw(decode_json);
use XML::LibXML;

my $json = decode_json( <<'JSON' );
{
	"first": "John",
	"last": "doe",
	"age": 26,
	"address": {
		"street": "naist street",
		"city": "Nara",
		"postcode": "630-0192"
	},
	"numbers": [
		{
			"type": "iPhone",
			"number": "0123-4567-8888",
			"things": [ "foo", "bar" ]
		},
		{
			"type": "home",
			"number": "0123-4567-8910",
			"things": [ "biff", "boff" ]
		},
		{
			"type": "work",
			"number": "0123-9999-8910"
		}
	],
	"typetest": {
		"numvalue": 30,
		"samenumvalue": 30,
		"list": [30, 30, 30, 30, 30, 30],
		"nullvalue": null,
		"falsevalue": false,
		"mediatype0": "application/pdf",
		"mediatype1": "application/pdf;charset=utf-8"
	}
}
JSON

my $xml = XML::LibXML->load_xml( string => <<'XML' );
<html>
 <body>
  <table>
   <tr id="tr1">
    <td id="td1.1">TD1.1</td>
    <td id="td1.2">TD1.2</td>
   </tr>
   <tr id="tr2" class="second">
    <td id="td2.1">TD2.1</td>
    <td id="td2.2">TD2.2</td>
   </tr>
   <tr id="tr3">
    <td id="td3.1">TD3.1</td>
    <td id="td3.2">TD3.2</td>
   </tr>
  </table>
  <person>
   <name>John</name>
   <age>26</age>
  </person>
  <rdf:seq xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" rdf:about="aboutvalue">
   <rdf:li>data</rdf:li>
  </rdf:seq>
 </body>
</html>
XML

subtest 'ported JSON cases from faceless2/zpath tests.txt' => sub {
	is( Data::ZPath->new('first')->first($json), 'John', 'first' );
	is( Data::ZPath->new('age')->first($json), 26, 'age' );
	is( scalar Data::ZPath->new('*')->all($json), 6, 'root wildcard count' );
	is( Data::ZPath->new('address/city')->first($json), 'Nara', 'address/city' );
	is( [ Data::ZPath->new('numbers/#0/things/*')->all($json) ], [ 'foo', 'bar' ], 'array traversal' );
	is( Data::ZPath->new('index(numbers/#1)')->first($json), 1, 'index() with index node' );
	is( Data::ZPath->new('count(numbers/*)')->first($json), 3, 'count' );
	is( [ Data::ZPath->new('first, first,last')->all($json) ], [ 'John', 'John', 'doe' ], 'comma list' );
	is( [ Data::ZPath->new('union(first, first,last)')->all($json) ], [ 'John', 'John', 'doe' ], 'union current behavior on primitives' );
	is( Data::ZPath->new('min(age)')->first($json), 26, 'min' );
	is( Data::ZPath->new('max(age)')->first($json), 26, 'max' );
	is( Data::ZPath->new('sum(age)')->first($json), 26, 'sum' );
	is( Data::ZPath->new('index-of("street", **/street)')->first($json), 6, 'index-of' );
	is( Data::ZPath->new('string-length(**/street)')->first($json), 12, 'string-length' );
	is( Data::ZPath->new('replace("(.*) street", "$1 road", **/street)')->first($json), '$1 road', 'replace' );
	is( Data::ZPath->new('upper-case(replace("^[^/]*/", "", replace(";.*", "", **/mediatype1)))')->first($json), 'PDF', 'upper-case' );
	is( Data::ZPath->new('join("|", numbers/#0/things/*)')->first($json), 'foo|bar', 'join' );
};

subtest 'ported XML cases from faceless2/zpath tests.txt' => sub {
	is( scalar Data::ZPath->new('html/body')->all($xml), 1, 'html/body' );
	is( scalar Data::ZPath->new('**/table/#2')->all($xml), 1, 'index segment' );
	is( Data::ZPath->new('count(**/tr)')->first($xml), 3, 'count tr' );
	is( [ Data::ZPath->new('**/td/@id')->all($xml) ], [ 'td1.1', 'td1.2', 'td2.1', 'td2.2', 'td3.1', 'td3.2' ], 'all td ids' );
	is( Data::ZPath->new('**/rdf:seq/@rdf:about')->first($xml), 'aboutvalue', 'namespaced attr' );
};

done_testing;
