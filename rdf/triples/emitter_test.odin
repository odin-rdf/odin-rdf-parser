package triples

import "core:mem"
import "core:strings"
import "core:testing"

import rdf ".."

@(test)
test_emit_exact_output :: proc(t: ^testing.T) {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	tr := rdf.Triple {
		subject   = rdf.IRI("http://s"),
		predicate = rdf.IRI("http://p"),
		object    = rdf.literal("a\nb\tc \"q\"", "en", rdf.Direction.LTR),
	}
	err := emit(w, tr)
	testing.expect(t, err == nil)
	testing.expect_value(t, strings.to_string(b), "<http://s> <http://p> \"a\\nb\\tc \\\"q\\\"\"@en--ltr .\n")
}

@(test)
test_emit_datatype_forms :: proc(t: ^testing.T) {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	// xsd:string is implicit; other datatypes are written explicitly.
	plain := rdf.Triple {
		subject   = rdf.Blank_Node("s"),
		predicate = rdf.IRI("http://p"),
		object    = rdf.literal("plain"),
	}
	typed := rdf.Triple {
		subject   = rdf.Blank_Node("s"),
		predicate = rdf.IRI("http://p"),
		object    = rdf.literal_typed("42", rdf.IRI(rdf.XSD_NS + "integer")),
	}
	testing.expect(t, emit(w, plain) == nil)
	testing.expect(t, emit(w, typed) == nil)
	expected := "_:s <http://p> \"plain\" .\n" +
		"_:s <http://p> \"42\"^^<http://www.w3.org/2001/XMLSchema#integer> .\n"
	testing.expect_value(t, strings.to_string(b), expected)
}

@(test)
test_round_trip :: proc(t: ^testing.T) {
	src := `<http://s> <http://p> <http://o> .
_:b <http://p> "plain" .
<http://s> <http://p> "esc\"quote\nline\ttab" .
<http://s> <http://p> "hallo"@de .
<http://s> <http://p> "chat"@fr--rtl .
<http://s> <http://p> "42"^^<http://www.w3.org/2001/XMLSchema#integer> .
_:r <http://p> <<( <http://s> <http://p> <<( _:x <http://p2> "o" )>> )>> .`

	originals: [dynamic]rdf.Triple
	defer {
		for tr in originals {
			rdf.destroy(tr)
		}
		delete(originals)
	}
	p: Parser
	parser_init(&p, transmute([]byte)src)
	for {
		tr, ok := parser_next(&p)
		if !ok {
			break
		}
		append(&originals, rdf.clone(tr))
	}
	testing.expect_value(t, p.err.kind, Error_Kind.None)
	testing.expect_value(t, len(originals), 7)
	parser_destroy(&p)

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	testing.expect(t, emit_all(strings.to_writer(&b), originals[:]) == nil)

	reparsed: [dynamic]rdf.Triple
	defer {
		for tr in reparsed {
			rdf.destroy(tr)
		}
		delete(reparsed)
	}
	p2: Parser
	parser_init(&p2, transmute([]byte)strings.to_string(b))
	for {
		tr, ok := parser_next(&p2)
		if !ok {
			break
		}
		append(&reparsed, rdf.clone(tr))
	}
	testing.expect_value(t, p2.err.kind, Error_Kind.None)
	parser_destroy(&p2)

	testing.expect_value(t, len(reparsed), len(originals))
	for tr, i in originals {
		testing.expectf(t, rdf.equal(tr, reparsed[i]), "statement %d differs after round trip", i)
	}
}

@(test)
test_emit_never_allocates :: proc(t: ^testing.T) {
	b := strings.builder_make() // builder owns its own (untracked) allocator
	defer strings.builder_destroy(&b)
	w := strings.to_writer(&b)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	inner := rdf.Triple {
		subject   = rdf.IRI("http://s"),
		predicate = rdf.IRI("http://p"),
		object    = rdf.literal("esc\naped", "ar", rdf.Direction.RTL),
	}
	tr := rdf.Triple {
		subject   = rdf.Blank_Node("r"),
		predicate = rdf.RDF_REIFIES,
		object    = &inner,
	}
	testing.expect(t, emit(w, tr) == nil)
	testing.expect_value(t, len(track.allocation_map), 0)
}
