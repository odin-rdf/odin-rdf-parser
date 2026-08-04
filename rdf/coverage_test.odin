package rdf

import "core:mem"
import "core:testing"

@(test)
test_two_level_triple_term_nesting :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	innermost := Triple {
		subject   = IRI("http://example.org/s"),
		predicate = IRI("http://example.org/p"),
		object    = literal("o"),
	}
	middle := Triple {
		subject   = Blank_Node("m"),
		predicate = RDF_REIFIES,
		object    = &innermost,
	}
	outer := Triple {
		subject   = Blank_Node("r"),
		predicate = RDF_REIFIES,
		object    = &middle,
	}

	owned := clone(outer, allocator)
	testing.expect(t, equal(owned, outer))
	testing.expect_value(t, hash(owned), hash(outer))

	// Mutating the original two levels down must not affect the clone.
	innermost.object = literal("changed")
	testing.expect(t, !equal(owned, outer))

	destroy(owned, allocator)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_clone_round_trip_each_term_kind :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	inner := Triple {
		subject   = IRI("http://example.org/s"),
		predicate = IRI("http://example.org/p"),
		object    = literal("o"),
	}
	kinds := [?]Term {
		IRI("http://example.org/i"),
		Blank_Node("b0"),
		literal("plain"),
		literal_typed("42", IRI(XSD_NS + "integer")),
		literal("hej", "sv"),
		literal("مرحبا", "ar", Direction.RTL),
		&inner,
	}

	for original in kinds {
		owned := clone(original, allocator)
		testing.expect(t, equal(owned, original))
		testing.expect_value(t, hash(owned), hash(original))
		destroy(owned, allocator)
	}

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_nil_term_and_graph_label :: proc(t: ^testing.T) {
	a, b: Term
	testing.expect(t, equal(a, b), "nil terms are equal to each other")
	testing.expect_value(t, hash(a), hash(b))
	testing.expect(t, !equal(a, Term(IRI(""))), "nil differs from an empty IRI")

	testing.expect(t, clone(a) == nil, "clone of nil is nil")
	destroy(a) // must be a safe no-op

	g, h: Graph_Label
	testing.expect(t, equal(g, h), "default graphs are equal")
	testing.expect(t, !equal(g, Graph_Label(IRI(""))), "default graph differs from empty IRI")
	testing.expect(t, clone(g) == nil)
	destroy(g) // must be a safe no-op
}
