// Throughput benchmarks for the parsers and emitters over deterministic
// generated corpora. Run with:
//
//	odin run bench -o:speed
//
// The CI-gating allocation guards live in tests/guards (odin test).
package main

import "core:fmt"
import "core:strings"
import "core:time"

import "corpus"
import rdf "../rdf"
import quads "../rdf/quads"
import trig "../rdf/trig"
import triples "../rdf/triples"
import turtle "../rdf/turtle"

STATEMENTS :: 200_000

main :: proc() {
	src_nt := corpus.generate_triples(STATEMENTS, false)
	defer delete(src_nt)
	src_nt_escaped := corpus.generate_triples(STATEMENTS, true)
	defer delete(src_nt_escaped)
	src_nq := corpus.generate_quads(STATEMENTS, false)
	defer delete(src_nq)
	src_ttl := corpus.generate_turtle(STATEMENTS)
	defer delete(src_ttl)
	src_ttl_struct := corpus.generate_turtle_structures(STATEMENTS)
	defer delete(src_ttl_struct)
	src_trig := corpus.generate_trig(STATEMENTS)
	defer delete(src_trig)

	bench_parse_triples("N-Triples parse (escape-free)", src_nt)
	bench_parse_triples("N-Triples parse (escaped)", src_nt_escaped)
	bench_parse_quads("N-Quads parse (escape-free)", src_nq)
	bench_emit_triples("N-Triples emit", src_nt)
	bench_emit_quads("N-Quads emit", src_nq)

	bench_parse_turtle("Turtle parse (prefixed-heavy)", src_ttl)
	bench_parse_turtle("Turtle parse (structure-heavy)", src_ttl_struct)
	bench_parse_trig("TriG parse (graph blocks)", src_trig)

	// The interning/expansion cost, apples to apples: the same dataset as
	// the prefixed corpus, flattened to N-Triples by the Turtle emitter.
	flat := flatten_turtle(src_ttl)
	defer delete(flat)
	bench_parse_triples("N-Triples parse (flat equivalent)", flat)

	bench_emit_turtle("Turtle emit (prefix-aware)", src_ttl)
	bench_emit_trig("TriG emit (graph blocks)", src_trig)
}

EX_PREFIXES := []turtle.Prefix{{"ex", "http://example.org/"}}

bench_parse_turtle :: proc(label: string, src: string) {
	start := time.tick_now()
	p: turtle.Parser
	turtle.parser_init(&p, transmute([]byte)src)
	count := 0
	for {
		_, ok := turtle.parser_next(&p)
		if !ok {
			break
		}
		count += 1
	}
	assert(p.err.kind == .None)
	turtle.parser_destroy(&p)
	report(label, count, len(src), time.tick_since(start))
}

bench_parse_trig :: proc(label: string, src: string) {
	start := time.tick_now()
	p: trig.Parser
	trig.parser_init(&p, transmute([]byte)src)
	count := 0
	for {
		_, ok := trig.parser_next(&p)
		if !ok {
			break
		}
		count += 1
	}
	assert(p.err.kind == .None)
	trig.parser_destroy(&p)
	report(label, count, len(src), time.tick_since(start))
}

// flatten_turtle rewrites the Turtle corpus as N-Triples via the flat
// (prefix-free) Turtle emitter path.
flatten_turtle :: proc(src: string) -> string {
	p: turtle.Parser
	turtle.parser_init(&p, transmute([]byte)src)
	defer turtle.parser_destroy(&p)
	b := strings.builder_make_len_cap(0, len(src) * 4)
	for {
		t, ok := turtle.parser_next(&p)
		if !ok {
			break
		}
		err := triples.emit(strings.to_writer(&b), t)
		assert(err == nil)
	}
	assert(p.err.kind == .None)
	return strings.to_string(b)
}

bench_emit_turtle :: proc(label: string, src: string) {
	statements: [dynamic]rdf.Triple
	defer {
		for stmt in statements {
			rdf.destroy(stmt)
		}
		delete(statements)
	}
	p: turtle.Parser
	turtle.parser_init(&p, transmute([]byte)src)
	for {
		stmt, ok := turtle.parser_next(&p)
		if !ok {
			break
		}
		append(&statements, rdf.clone(stmt))
	}
	turtle.parser_destroy(&p)

	b := strings.builder_make_len_cap(0, len(src) + len(src) / 8)
	defer strings.builder_destroy(&b)
	start := time.tick_now()
	e: turtle.Emitter
	err := turtle.emitter_init(&e, strings.to_writer(&b), EX_PREFIXES)
	assert(err == nil)
	defer turtle.emitter_destroy(&e)
	for stmt in statements {
		emit_err := turtle.emit(&e, stmt)
		assert(emit_err == nil)
	}
	assert(turtle.emitter_finish(&e) == nil)
	report(label, len(statements), strings.builder_len(b), time.tick_since(start))
}

bench_emit_trig :: proc(label: string, src: string) {
	statements: [dynamic]rdf.Quad
	defer {
		for stmt in statements {
			rdf.destroy(stmt)
		}
		delete(statements)
	}
	p: trig.Parser
	trig.parser_init(&p, transmute([]byte)src)
	for {
		stmt, ok := trig.parser_next(&p)
		if !ok {
			break
		}
		append(&statements, rdf.clone(stmt))
	}
	trig.parser_destroy(&p)

	b := strings.builder_make_len_cap(0, len(src) + len(src) / 2)
	defer strings.builder_destroy(&b)
	start := time.tick_now()
	e: trig.Emitter
	err := trig.emitter_init(&e, strings.to_writer(&b), EX_PREFIXES)
	assert(err == nil)
	defer trig.emitter_destroy(&e)
	for stmt in statements {
		emit_err := trig.emit(&e, stmt)
		assert(emit_err == nil)
	}
	assert(trig.emitter_finish(&e) == nil)
	report(label, len(statements), strings.builder_len(b), time.tick_since(start))
}

bench_parse_triples :: proc(label: string, src: string) {
	start := time.tick_now()
	p: triples.Parser
	triples.parser_init(&p, transmute([]byte)src)
	count := 0
	for {
		_, ok := triples.parser_next(&p)
		if !ok {
			break
		}
		count += 1
	}
	assert(p.err.kind == .None)
	triples.parser_destroy(&p)
	report(label, count, len(src), time.tick_since(start))
}

bench_parse_quads :: proc(label: string, src: string) {
	start := time.tick_now()
	p: quads.Parser
	quads.parser_init(&p, transmute([]byte)src)
	count := 0
	for {
		_, ok := quads.parser_next(&p)
		if !ok {
			break
		}
		count += 1
	}
	assert(p.err.kind == .None)
	quads.parser_destroy(&p)
	report(label, count, len(src), time.tick_since(start))
}

bench_emit_triples :: proc(label: string, src: string) {
	statements: [dynamic]rdf.Triple
	defer {
		for stmt in statements {
			rdf.destroy(stmt)
		}
		delete(statements)
	}
	p: triples.Parser
	triples.parser_init(&p, transmute([]byte)src)
	for {
		stmt, ok := triples.parser_next(&p)
		if !ok {
			break
		}
		append(&statements, rdf.clone(stmt))
	}
	triples.parser_destroy(&p)

	b := strings.builder_make_len_cap(0, len(src) + len(src) / 8)
	defer strings.builder_destroy(&b)
	start := time.tick_now()
	err := triples.emit_all(strings.to_writer(&b), statements[:])
	assert(err == nil)
	report(label, len(statements), strings.builder_len(b), time.tick_since(start))
}

bench_emit_quads :: proc(label: string, src: string) {
	statements: [dynamic]rdf.Quad
	defer {
		for stmt in statements {
			rdf.destroy(stmt)
		}
		delete(statements)
	}
	p: quads.Parser
	quads.parser_init(&p, transmute([]byte)src)
	for {
		stmt, ok := quads.parser_next(&p)
		if !ok {
			break
		}
		append(&statements, rdf.clone(stmt))
	}
	quads.parser_destroy(&p)

	b := strings.builder_make_len_cap(0, len(src) + len(src) / 8)
	defer strings.builder_destroy(&b)
	start := time.tick_now()
	err := quads.emit_all(strings.to_writer(&b), statements[:])
	assert(err == nil)
	report(label, len(statements), strings.builder_len(b), time.tick_since(start))
}

report :: proc(label: string, statements: int, bytes: int, d: time.Duration) {
	secs := time.duration_seconds(d)
	fmt.printfln(
		"%-32s %11.0f stmts/s %8.1f MB/s   (%d statements, %v)",
		label,
		f64(statements) / secs,
		f64(bytes) / secs / 1e6,
		statements,
		d,
	)
}
