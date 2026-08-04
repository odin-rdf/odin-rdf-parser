package rdf

import "core:testing"

@(test)
test_equal_is_buffer_independent :: proc(t: ^testing.T) {
	source := "http://example.org/s"
	buf_a := make([]byte, len(source))
	defer delete(buf_a)
	buf_b := make([]byte, len(source))
	defer delete(buf_b)
	copy(buf_a, source)
	copy(buf_b, source)

	a := Term(IRI(string(buf_a)))
	b := Term(IRI(string(buf_b)))
	testing.expect(t, equal(a, b), "same content in different buffers must be equal")
	testing.expect_value(t, hash(a), hash(b))
}

@(test)
test_equal_distinguishes_kinds_and_components :: proc(t: ^testing.T) {
	// Same lexical content, different kind.
	testing.expect(t, !equal(Term(IRI("x")), Term(Blank_Node("x"))))
	testing.expect(t, hash(Term(IRI("x"))) != hash(Term(Blank_Node("x"))))

	// Literal corner cases: same lexical form, different datatype /
	// language / direction must all differ.
	plain := Term(literal("chat"))
	tagged := Term(literal("chat", "fr"))
	directed := Term(literal("chat", "fr", Direction.LTR))
	typed := Term(literal_typed("chat", IRI(XSD_NS + "token")))

	testing.expect(t, !equal(plain, tagged))
	testing.expect(t, !equal(tagged, directed))
	testing.expect(t, !equal(plain, typed))
	testing.expect(t, hash(plain) != hash(tagged))
	testing.expect(t, hash(tagged) != hash(directed))
	testing.expect(t, hash(plain) != hash(typed))

	// Positive cases hash identically.
	testing.expect(t, equal(tagged, Term(literal("chat", "fr"))))
	testing.expect_value(t, hash(tagged), hash(Term(literal("chat", "fr"))))
}

@(test)
test_equal_recurses_through_triple_terms :: proc(t: ^testing.T) {
	inner_a := Triple {
		subject   = IRI("http://example.org/s"),
		predicate = IRI("http://example.org/p"),
		object    = literal("o"),
	}
	inner_b := inner_a // same structure, distinct address

	a := Term(&inner_a)
	b := Term(&inner_b)

	testing.expect(t, a != b, "built-in == compares triple terms by pointer")
	testing.expect(t, equal(a, b), "equal compares triple terms by structure")
	testing.expect_value(t, hash(a), hash(b))

	// Same-pointer fast path.
	testing.expect(t, equal(a, Term(&inner_a)))

	// Structural difference one level down.
	inner_b.object = literal("different")
	testing.expect(t, !equal(a, b))
	testing.expect(t, hash(a) != hash(b))
}

@(test)
test_quad_equality_with_graph_labels :: proc(t: ^testing.T) {
	tr := Triple {
		subject   = IRI("http://example.org/s"),
		predicate = IRI("http://example.org/p"),
		object    = literal("o"),
	}
	default_a := Quad{triple = tr}
	default_b := Quad{triple = tr}
	named := Quad{triple = tr, graph = IRI("http://example.org/g")}
	bnode_graph := Quad{triple = tr, graph = Blank_Node("http://example.org/g")}

	testing.expect(t, equal(default_a, default_b), "default-graph quads must be equal")
	testing.expect_value(t, hash(default_a), hash(default_b))

	testing.expect(t, !equal(default_a, named), "default graph differs from named graph")
	testing.expect(t, !equal(named, bnode_graph), "graph label kind matters")
	testing.expect(t, hash(default_a) != hash(named))
	testing.expect(t, hash(named) != hash(bnode_graph))
}
