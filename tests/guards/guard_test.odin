// Package guards holds the CI-gating allocation guards for the zero-copy
// promise (ADR RDF-A-0001): an accidental copy in a future change fails
// these tests instead of regressing silently. Throughput benchmarks live
// in bench/ (run with `odin run bench`).
package guards

import "core:mem"
import "core:testing"

import corpus "../../bench/corpus"
import quads "../../rdf/quads"
import trig "../../rdf/trig"
import triples "../../rdf/triples"
import turtle "../../rdf/turtle"

STATEMENTS :: 10_000

@(test)
test_ntriples_escape_free_zero_allocations :: proc(t: ^testing.T) {
	original_allocator := context.allocator
	src := corpus.generate_triples(STATEMENTS, false)
	defer delete(src, original_allocator)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)
	context.allocator = allocator

	p: triples.Parser
	triples.parser_init(&p, transmute([]byte)src, allocator)
	count := 0
	for {
		_, ok := triples.parser_next(&p)
		if !ok {
			break
		}
		count += 1
	}
	testing.expect_value(t, count, STATEMENTS)
	testing.expect_value(t, p.err.kind, triples.Error_Kind.None)
	testing.expect(t, track.total_allocation_count == 0, "escape-free parse must not allocate at all")
	triples.parser_destroy(&p)
}

@(test)
test_nquads_escape_free_zero_allocations :: proc(t: ^testing.T) {
	original_allocator := context.allocator
	src := corpus.generate_quads(STATEMENTS, false)
	defer delete(src, original_allocator)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)
	context.allocator = allocator

	p: quads.Parser
	quads.parser_init(&p, transmute([]byte)src, allocator)
	count := 0
	for {
		_, ok := quads.parser_next(&p)
		if !ok {
			break
		}
		count += 1
	}
	testing.expect_value(t, count, STATEMENTS)
	testing.expect_value(t, p.err.kind, quads.Error_Kind.None)
	testing.expect(t, track.total_allocation_count == 0, "escape-free parse must not allocate at all")
	quads.parser_destroy(&p)
}

// The Turtle corpus is fully cyclic (period corpus.TURTLE_CYCLE), so
// after one cycle plus one statement the intern table, prefix map,
// scratch buffers, and statement queue are all at their high-water
// marks — every allocation after that is a regression. Interning
// effectiveness is asserted exactly: the intern table ends with one
// entry per distinct IRI (plus the prefix binding), never one per
// occurrence.
@(test)
test_turtle_interning_and_steady_state :: proc(t: ^testing.T) {
	original_allocator := context.allocator
	src := corpus.generate_turtle(STATEMENTS)
	defer delete(src, original_allocator)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	p: turtle.Parser
	turtle.parser_init(&p, transmute([]byte)src, "", allocator)

	// 3 triples per statement; drain one full cycle plus one statement.
	warmup := (corpus.TURTLE_CYCLE + 1) * 3
	count := 0
	for count < warmup {
		_, ok := turtle.parser_next(&p)
		testing.expect(t, ok)
		count += 1
	}
	high_water := track.total_allocation_count
	for {
		_, ok := turtle.parser_next(&p)
		if !ok {
			break
		}
		count += 1
	}
	testing.expect_value(t, p.err.kind, turtle.Error_Kind.None)
	testing.expect_value(t, count, STATEMENTS * 3)
	testing.expectf(
		t,
		track.total_allocation_count == high_water,
		"steady-state Turtle parse allocated: %v -> %v",
		high_water,
		track.total_allocation_count,
	)
	// Interning effectiveness: 30k IRI occurrences in the document, one
	// materialization per distinct string in the table.
	testing.expect_value(t, len(p.core.intern.entries), corpus.TURTLE_DISTINCT_IRIS)

	turtle.parser_destroy(&p)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_trig_graph_blocks_steady_state :: proc(t: ^testing.T) {
	original_allocator := context.allocator
	src := corpus.generate_trig(STATEMENTS)
	defer delete(src, original_allocator)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	p: trig.Parser
	trig.parser_init(&p, transmute([]byte)src, "", allocator)

	warmup := (corpus.TURTLE_CYCLE + 1) * 3
	count := 0
	for count < warmup {
		_, ok := trig.parser_next(&p)
		testing.expect(t, ok)
		count += 1
	}
	high_water := track.total_allocation_count
	for {
		_, ok := trig.parser_next(&p)
		if !ok {
			break
		}
		count += 1
	}
	testing.expect_value(t, p.err.kind, trig.Error_Kind.None)
	testing.expect_value(t, count, STATEMENTS * 3)
	testing.expectf(
		t,
		track.total_allocation_count == high_water,
		"steady-state TriG parse allocated: %v -> %v",
		high_water,
		track.total_allocation_count,
	)

	trig.parser_destroy(&p)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_ntriples_escaped_exact_allocation_count :: proc(t: ^testing.T) {
	original_allocator := context.allocator
	src := corpus.generate_triples(STATEMENTS, true)
	defer delete(src, original_allocator)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)
	context.allocator = allocator

	p: triples.Parser
	triples.parser_init(&p, transmute([]byte)src, allocator)
	count := 0
	for {
		_, ok := triples.parser_next(&p)
		if !ok {
			break
		}
		count += 1
	}
	testing.expect_value(t, count, STATEMENTS)
	testing.expect_value(t, p.err.kind, triples.Error_Kind.None)
	// Exactly one unescape buffer per escaped token, plus one backing
	// allocation for the parser's owned-strings list (its capacity is
	// reused across statements).
	testing.expect_value(t, int(track.total_allocation_count), STATEMENTS + 1)

	triples.parser_destroy(&p)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}
