package triples

import "core:mem"
import "core:testing"

import rdf ".."

parse_all :: proc(p: ^Parser, source: string, allocator := context.allocator) -> int {
	parser_init(p, transmute([]byte)source, allocator)
	count := 0
	for {
		_, ok := parser_next(p)
		if !ok {
			break
		}
		count += 1
	}
	return count
}

@(test)
test_parses_all_term_kinds :: proc(t: ^testing.T) {
	src := `<http://a> <http://p> <http://o> .
_:s <http://p> "plain" . # comment
<http://a> <http://p> "hallo"@de .
<http://a> <http://p> "chat"@fr--ltr .
<http://a> <http://p> "42"^^<http://www.w3.org/2001/XMLSchema#integer> .
<http://a> <http://p> _:o .`

	p: Parser
	defer parser_destroy(&p)
	parser_init(&p, transmute([]byte)src)

	first, ok1 := parser_next(&p)
	testing.expect(t, ok1)
	testing.expect(t, rdf.equal(first.subject, rdf.Term(rdf.IRI("http://a"))))
	testing.expect(t, rdf.equal(first.object, rdf.Term(rdf.IRI("http://o"))))

	second, ok2 := parser_next(&p)
	testing.expect(t, ok2)
	testing.expect(t, rdf.equal(second.subject, rdf.Term(rdf.Blank_Node("s"))))
	testing.expect(t, rdf.equal(second.object, rdf.Term(rdf.literal("plain"))))

	third, ok3 := parser_next(&p)
	testing.expect(t, ok3)
	testing.expect(t, rdf.equal(third.object, rdf.Term(rdf.literal("hallo", "de"))))

	fourth, ok4 := parser_next(&p)
	testing.expect(t, ok4)
	testing.expect(t, rdf.equal(fourth.object, rdf.Term(rdf.literal("chat", "fr", rdf.Direction.LTR))))

	fifth, ok5 := parser_next(&p)
	testing.expect(t, ok5)
	want := rdf.literal_typed("42", rdf.IRI(rdf.XSD_NS + "integer"))
	testing.expect(t, rdf.equal(fifth.object, rdf.Term(want)))

	sixth, ok6 := parser_next(&p)
	testing.expect(t, ok6)
	testing.expect(t, rdf.equal(sixth.object, rdf.Term(rdf.Blank_Node("o"))))

	_, ok7 := parser_next(&p)
	testing.expect(t, !ok7)
	testing.expect_value(t, p.err.kind, Error_Kind.None)
}

@(test)
test_unescaping :: proc(t: ^testing.T) {
	src := `<http://a/` + "\\" + `u0041> <http://p> "line1\nline2 \"q\" back\\slash" .`

	p: Parser
	defer parser_destroy(&p)
	parser_init(&p, transmute([]byte)src)

	triple, ok := parser_next(&p)
	testing.expect(t, ok)
	testing.expect(t, rdf.equal(triple.subject, rdf.Term(rdf.IRI("http://a/A"))))
	lit := triple.object.(rdf.Literal)
	testing.expect_value(t, lit.lexical, "line1\nline2 \"q\" back\\slash")
}

@(test)
test_triple_terms_nested :: proc(t: ^testing.T) {
	src := `_:r <http://www.w3.org/1999/02/22-rdf-syntax-ns#reifies> <<( <http://s> <http://p> <<( <http://s2> <http://p2> "o2" )>> )>> .`

	p: Parser
	defer parser_destroy(&p)
	parser_init(&p, transmute([]byte)src)

	triple, ok := parser_next(&p)
	testing.expect(t, ok)
	outer, is_tt := triple.object.(^rdf.Triple)
	testing.expect(t, is_tt)
	testing.expect(t, rdf.equal(outer.subject, rdf.Term(rdf.IRI("http://s"))))
	inner, is_inner_tt := outer.object.(^rdf.Triple)
	testing.expect(t, is_inner_tt)
	testing.expect(t, rdf.equal(inner.object, rdf.Term(rdf.literal("o2"))))
}

@(test)
test_zero_allocation_without_escapes :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)
	context.allocator = allocator

	src := `<http://a> <http://p> "plain"@en--rtl .
_:s <http://p> "x"^^<http://www.w3.org/2001/XMLSchema#string> .`

	p: Parser
	count := parse_all(&p, src, allocator)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, p.err.kind, Error_Kind.None)
	testing.expect_value(t, len(track.allocation_map), 0)
	parser_destroy(&p)
}

@(test)
test_cow_allocations_freed :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	src := `<http://a> <http://p> "one\n" .
<http://a> <http://p> "two\t" .
<http://a> <http://p> <<( <http://s> <http://p> "o" )>> .`

	p: Parser
	count := parse_all(&p, src, allocator)
	testing.expect_value(t, count, 3)
	parser_destroy(&p)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_statement_may_span_lines :: proc(t: ^testing.T) {
	// Newlines are inter-token whitespace (documented scanner decision).
	src := "<http://a>\n  <http://p>\n  \"o\" ."
	p: Parser
	count := parse_all(&p, src)
	defer parser_destroy(&p)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, p.err.kind, Error_Kind.None)
}

@(test)
test_parser_errors :: proc(t: ^testing.T) {
	cases := [?]struct {
		src:  string,
		kind: Error_Kind,
	} {
		{`<http://a>`, .Expected_Predicate},
		{`<http://a> <http://p>`, .Expected_Object},
		{`<http://a> <http://p> <http://o>`, .Expected_Dot},
		{`"lit" <http://p> <http://o> .`, .Expected_Subject},
		{`<http://a> _:p <http://o> .`, .Expected_Predicate},
		{`<http://a> <http://p> <http://o> <http://g> .`, .Expected_Dot},
		{`<http://a> <http://p> "x"@fr--xxx .`, .Invalid_Direction},
		{`<http://a> <http://p> "x"^^"y" .`, .Expected_Datatype},
		{`<http://a> <http://p> <<( <http://s> <http://p> "o" .`, .Unclosed_Triple_Term},
		{`<http://a> <http://p> "unterminated`, .Unterminated_String},
		{`<http://a> <http://p> .`, .Expected_Object},
	}
	for c in cases {
		p: Parser
		parse_all(&p, c.src)
		testing.expectf(t, p.err.kind == c.kind, "%q: got %v, want %v", c.src, p.err.kind, c.kind)

		// Errors are sticky.
		_, again := parser_next(&p)
		testing.expect(t, !again)
		parser_destroy(&p)
	}
}

@(test)
test_error_position :: proc(t: ^testing.T) {
	src := "<http://a> <http://p> <http://o> .\n<http://a> \"bad\" <http://o> ."
	p: Parser
	defer parser_destroy(&p)
	parse_all(&p, src)
	testing.expect_value(t, p.err.kind, Error_Kind.Expected_Predicate)
	testing.expect_value(t, p.err.line, 2)
	testing.expect_value(t, p.err.column, 12)
}
