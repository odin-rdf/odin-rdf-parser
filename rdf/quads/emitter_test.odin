package quads

import "core:strings"
import "core:testing"

import rdf ".."

@(test)
test_emit_graph_label_forms :: proc(t: ^testing.T) {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	base := rdf.Triple {
		subject   = rdf.IRI("http://s"),
		predicate = rdf.IRI("http://p"),
		object    = rdf.literal("o"),
	}
	named := rdf.Quad{triple = base, graph = rdf.IRI("http://g")}
	bnode := rdf.Quad{triple = base, graph = rdf.Blank_Node("g")}
	dflt := rdf.Quad{triple = base}

	testing.expect(t, emit(w, named) == nil)
	testing.expect(t, emit(w, bnode) == nil)
	testing.expect(t, emit(w, dflt) == nil)

	expected := "<http://s> <http://p> \"o\" <http://g> .\n" +
		"<http://s> <http://p> \"o\" _:g .\n" +
		"<http://s> <http://p> \"o\" .\n"
	testing.expect_value(t, strings.to_string(b), expected)
}

@(test)
test_round_trip :: proc(t: ^testing.T) {
	src := `<http://s> <http://p> "o" <http://g> .
<http://s> <http://p> "esc\n" _:g .
_:r <http://p> <<( <http://s> <http://p> "o"@fr--ltr )>> .
<http://s> <http://p> "42"^^<http://www.w3.org/2001/XMLSchema#integer> <http://g> .`

	originals: [dynamic]rdf.Quad
	defer {
		for q in originals {
			rdf.destroy(q)
		}
		delete(originals)
	}
	p: Parser
	parser_init(&p, transmute([]byte)src)
	for {
		q, ok := parser_next(&p)
		if !ok {
			break
		}
		append(&originals, rdf.clone(q))
	}
	testing.expect_value(t, p.err.kind, Error_Kind.None)
	testing.expect_value(t, len(originals), 4)
	parser_destroy(&p)

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	testing.expect(t, emit_all(strings.to_writer(&b), originals[:]) == nil)

	reparsed: [dynamic]rdf.Quad
	defer {
		for q in reparsed {
			rdf.destroy(q)
		}
		delete(reparsed)
	}
	p2: Parser
	parser_init(&p2, transmute([]byte)strings.to_string(b))
	for {
		q, ok := parser_next(&p2)
		if !ok {
			break
		}
		append(&reparsed, rdf.clone(q))
	}
	testing.expect_value(t, p2.err.kind, Error_Kind.None)
	parser_destroy(&p2)

	testing.expect_value(t, len(reparsed), len(originals))
	for q, i in originals {
		testing.expectf(t, rdf.equal(q, reparsed[i]), "statement %d differs after round trip", i)
	}
}
