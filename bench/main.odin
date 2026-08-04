// Throughput benchmarks for the line-based parsers and emitters over
// deterministic generated corpora. Run with:
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
import triples "../rdf/triples"

STATEMENTS :: 200_000

main :: proc() {
	src_nt := corpus.generate_triples(STATEMENTS, false)
	defer delete(src_nt)
	src_nt_escaped := corpus.generate_triples(STATEMENTS, true)
	defer delete(src_nt_escaped)
	src_nq := corpus.generate_quads(STATEMENTS, false)
	defer delete(src_nq)

	bench_parse_triples("N-Triples parse (escape-free)", src_nt)
	bench_parse_triples("N-Triples parse (escaped)", src_nt_escaped)
	bench_parse_quads("N-Quads parse (escape-free)", src_nq)
	bench_emit_triples("N-Triples emit", src_nt)
	bench_emit_quads("N-Quads emit", src_nq)
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
