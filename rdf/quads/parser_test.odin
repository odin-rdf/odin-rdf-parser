package quads

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
test_graph_label_cases :: proc(t: ^testing.T) {
	src := `<http://s> <http://p> "o" <http://g> .
<http://s> <http://p> "o" _:g .
<http://s> <http://p> "o" .`

	p: Parser
	defer parser_destroy(&p)
	parser_init(&p, transmute([]byte)src)

	named, ok1 := parser_next(&p)
	testing.expect(t, ok1)
	testing.expect(t, rdf.equal(named.graph, rdf.Graph_Label(rdf.IRI("http://g"))))
	testing.expect(t, rdf.equal(named.subject, rdf.Term(rdf.IRI("http://s"))))

	bnode, ok2 := parser_next(&p)
	testing.expect(t, ok2)
	testing.expect(t, rdf.equal(bnode.graph, rdf.Graph_Label(rdf.Blank_Node("g"))))

	dflt, ok3 := parser_next(&p)
	testing.expect(t, ok3)
	testing.expect(t, dflt.graph == nil)

	_, ok4 := parser_next(&p)
	testing.expect(t, !ok4)
	testing.expect_value(t, p.err.kind, Error_Kind.None)
}

@(test)
test_triple_term_in_quad :: proc(t: ^testing.T) {
	src := `_:r <http://www.w3.org/1999/02/22-rdf-syntax-ns#reifies> <<( <http://s> <http://p> "o" )>> <http://g> .`

	p: Parser
	defer parser_destroy(&p)
	parser_init(&p, transmute([]byte)src)

	quad, ok := parser_next(&p)
	testing.expect(t, ok)
	tt, is_tt := quad.object.(^rdf.Triple)
	testing.expect(t, is_tt)
	testing.expect(t, rdf.equal(tt.object, rdf.Term(rdf.literal("o"))))
	testing.expect(t, rdf.equal(quad.graph, rdf.Graph_Label(rdf.IRI("http://g"))))
}

@(test)
test_zero_allocation_without_escapes :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)
	context.allocator = allocator

	src := `<http://s> <http://p> "o"@en <http://g> .
<http://s> <http://p> "o" _:g .`

	p: Parser
	count := parse_all(&p, src, allocator)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, p.err.kind, Error_Kind.None)
	testing.expect_value(t, len(track.allocation_map), 0)
	parser_destroy(&p)
}

@(test)
test_escaped_graph_label_freed :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	src := `<http://s> <http://p> "o" <http://g/` + "\\" + `u0041> .`

	p: Parser
	parser_init(&p, transmute([]byte)src, allocator)
	quad, ok := parser_next(&p)
	testing.expect(t, ok)
	testing.expect(t, rdf.equal(quad.graph, rdf.Graph_Label(rdf.IRI("http://g/A"))))
	parser_destroy(&p)
	testing.expect_value(t, len(track.allocation_map), 0)
}

@(test)
test_quad_errors :: proc(t: ^testing.T) {
	cases := [?]struct {
		src:  string,
		kind: Error_Kind,
	} {
		{`<http://s> <http://p> "o" "g" .`, .Invalid_Graph_Label},
		{`<http://s> <http://p> "o" <http://g> <http://x> .`, .Expected_Dot},
		{`<http://s> <http://p> "o" <http://g>`, .Expected_Dot},
		{`<http://s> <http://p> .`, .Expected_Object},
		{`<http://s> <http://p> "o" <bad iri> .`, .Invalid_IRI_Character},
	}
	for c in cases {
		p: Parser
		parse_all(&p, c.src)
		testing.expectf(t, p.err.kind == c.kind, "%q: got %v, want %v", c.src, p.err.kind, c.kind)
		_, again := parser_next(&p)
		testing.expect(t, !again)
		parser_destroy(&p)
	}
}
