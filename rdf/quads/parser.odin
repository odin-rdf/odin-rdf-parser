// Package quads parses and emits the W3C N-Quads format (RDF 1.2),
// including RDF-star triple terms.
//
// Parsing is streaming and zero-copy with the same contracts as
// rdf/triples: borrowed slices by default, copy-on-write unescaping, and
// per-statement validity — a yielded quad is valid only until the next
// parser_next call or parser_destroy (ADR RDF-A-0001).
package quads

import rdf ".."
import scan "../internal/scanner"
import st "../internal/statement"

// Error and Error_Kind are shared with the scanner and the triples package.
Error :: scan.Error
Error_Kind :: scan.Error_Kind
// error_message returns a static description of an error kind.
error_message :: scan.error_message

// Parser is a streaming N-Quads pull parser over a caller-owned buffer.
// After parser_next returns false, err.kind distinguishes clean end of
// input (.None) from a syntax error. Errors are sticky: once set,
// parser_next keeps returning false.
Parser :: struct {
	using core: st.Parser,
}

parser_init :: proc(p: ^Parser, source: []byte, allocator := context.allocator) {
	st.init(&p.core, source, allocator)
}

parser_destroy :: proc(p: ^Parser) {
	st.destroy(&p.core)
}

// parser_next yields the next quad; an absent graph label yields a nil
// Graph_Label (the default graph). The result is valid until the next
// call or parser_destroy. ok is false at end of input or on error; check
// p.err.kind to distinguish (.None means clean end).
parser_next :: proc(p: ^Parser) -> (quad: rdf.Quad, ok: bool) {
	if p.err.kind != .None {
		return {}, false
	}
	st.free_statement(&p.core)

	subject, sok := st.parse_subject(&p.core)
	if !sok {
		return {}, false
	}
	predicate, pok := st.parse_predicate(&p.core)
	if !pok {
		return {}, false
	}
	object, ook := st.parse_object(&p.core)
	if !ook {
		return {}, false
	}
	graph, gok := st.parse_optional_graph_label(&p.core)
	if !gok {
		return {}, false
	}
	if !st.expect_dot(&p.core) {
		return {}, false
	}
	quad = {
		triple = {subject = subject, predicate = predicate, object = object},
		graph  = graph,
	}
	return quad, true
}
