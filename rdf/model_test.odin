package rdf

import "core:testing"

@(test)
test_literal_constructors :: proc(t: ^testing.T) {
	plain := literal("hello")
	testing.expect_value(t, plain.datatype, XSD_STRING)
	testing.expect_value(t, plain.language, "")
	testing.expect_value(t, plain.direction, Direction.None)

	typed := literal_typed("42", IRI(XSD_NS + "integer"))
	testing.expect_value(t, typed.lexical, "42")
	testing.expect_value(t, typed.datatype, IRI(XSD_NS + "integer"))

	tagged := literal("hallo", "de")
	testing.expect_value(t, tagged.datatype, RDF_LANG_STRING)
	testing.expect_value(t, tagged.language, "de")
	testing.expect_value(t, tagged.direction, Direction.None)

	directed := literal("שלום", "he", Direction.RTL)
	testing.expect_value(t, directed.datatype, RDF_DIR_LANG_STRING)
	testing.expect_value(t, directed.language, "he")
	testing.expect_value(t, directed.direction, Direction.RTL)
}

@(test)
test_quad_embeds_triple :: proc(t: ^testing.T) {
	q := Quad {
		triple = {
			subject   = IRI("http://example.org/s"),
			predicate = RDF_TYPE,
			object    = literal("x"),
		},
		graph = IRI("http://example.org/g"),
	}

	// Triple fields reachable directly on the quad via `using`.
	testing.expect_value(t, q.subject, Term(IRI("http://example.org/s")))
	testing.expect_value(t, q.predicate, Term(RDF_TYPE))
	testing.expect_value(t, q.graph, Graph_Label(IRI("http://example.org/g")))
}

@(test)
test_default_graph_is_nil :: proc(t: ^testing.T) {
	q: Quad
	testing.expect(t, q.graph == nil)
}

@(test)
test_triple_term_nesting :: proc(t: ^testing.T) {
	inner := Triple {
		subject   = IRI("http://example.org/s"),
		predicate = IRI("http://example.org/p"),
		object    = literal("o"),
	}
	outer := Triple {
		subject   = Blank_Node("b0"),
		predicate = RDF_REIFIES,
		object    = &inner,
	}

	tt, is_triple_term := outer.object.(^Triple)
	testing.expect(t, is_triple_term)
	testing.expect_value(t, tt.subject, Term(IRI("http://example.org/s")))
}
