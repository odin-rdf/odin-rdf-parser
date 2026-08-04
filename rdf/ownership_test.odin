package rdf

import "core:mem"
import "core:testing"

@(test)
test_clone_survives_buffer_overwrite :: proc(t: ^testing.T) {
	source := "http://example.org/s"
	buf := make([]byte, len(source))
	defer delete(buf)
	copy(buf, source)

	borrowed := Triple {
		subject   = IRI(string(buf)),
		predicate = RDF_TYPE,
		object    = literal("hallo", "de"),
	}
	owned := clone(borrowed)
	defer destroy(owned)

	for &b in buf {
		b = 'x'
	}

	testing.expect_value(t, owned.subject, Term(IRI("http://example.org/s")))
	testing.expect_value(t, owned.object, Term(literal("hallo", "de")))
	// The borrowed original now sees the overwritten buffer.
	testing.expect_value(t, borrowed.subject, Term(IRI("xxxxxxxxxxxxxxxxxxxx")))
}

@(test)
test_clone_destroy_leak_free :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	inner := Triple {
		subject   = IRI("http://example.org/s"),
		predicate = IRI("http://example.org/p"),
		object    = literal("שלום", "he", Direction.RTL),
	}
	q := Quad {
		triple = {
			subject   = Blank_Node("b0"),
			predicate = RDF_REIFIES,
			object    = &inner,
		},
		graph = IRI("http://example.org/g"),
	}

	owned := clone(q, allocator)
	testing.expect(t, len(track.allocation_map) > 0)
	destroy(owned, allocator)

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_intern_deduplicates :: proc(t: ^testing.T) {
	table: Intern_Table
	intern_table_init(&table)
	defer intern_table_destroy(&table)

	a := intern(&table, "http://example.org/s")
	b := intern(&table, "http://example.org/s")
	c := intern(&table, "http://example.org/other")

	testing.expect_value(t, a, "http://example.org/s")
	testing.expect(t, raw_data(a) == raw_data(b), "equal content must share backing storage")
	testing.expect(t, raw_data(a) != raw_data(c))
	testing.expect_value(t, len(table.entries), 2)
}

@(test)
test_intern_table_leak_free :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	inner := Triple {
		subject   = IRI("http://example.org/s"),
		predicate = IRI("http://example.org/p"),
		object    = literal("o"),
	}
	q := Quad {
		triple = {
			subject   = IRI("http://example.org/s"), // repeated content
			predicate = RDF_REIFIES,
			object    = &inner,
		},
		graph = Blank_Node("g0"),
	}

	table: Intern_Table
	intern_table_init(&table, allocator)
	owned := intern_quad(&table, q)

	tt, is_triple_term := owned.object.(^Triple)
	testing.expect(t, is_triple_term)
	// Repeated IRI content shares storage across the whole statement.
	testing.expect(
		t,
		raw_data(string(owned.subject.(IRI))) == raw_data(string(tt.subject.(IRI))),
		"interned repeats must share backing storage",
	)

	intern_table_destroy(&table)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}
