// Package guards holds the CI-gating allocation guards for the zero-copy
// promise (ADR RDF-A-0001): an accidental copy in a future change fails
// these tests instead of regressing silently. Throughput benchmarks live
// in bench/ (run with `odin run bench`).
package guards

import "core:mem"
import "core:testing"

import corpus "../../bench/corpus"
import quads "../../rdf/quads"
import triples "../../rdf/triples"

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
