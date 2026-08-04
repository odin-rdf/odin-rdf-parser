// Package triples parses and emits the W3C N-Triples format (RDF 1.2),
// including RDF-star triple terms.
//
// Parsing is streaming and zero-copy: term strings in a yielded triple
// are borrowed slices of the source buffer, except escaped tokens, which
// are unescaped into memory owned by the parser. A yielded triple is
// valid only until the next parser_next call or parser_destroy — keep
// statements with rdf.clone or an rdf.Intern_Table (ADR RDF-A-0001).
//
// The input is the complete document in one caller-owned buffer
// (RDF-T-0024); for large files, memory-map the file and pass the
// mapping. The quad-based sibling format is rdf/quads; the abbreviated
// human-readable format is rdf/turtle.
package triples

import rdf ".."
import scan "../internal/scanner"
import st "../internal/statement"

// Error and Error_Kind are shared with the scanner and the quads package.
Error :: scan.Error
Error_Kind :: scan.Error_Kind
// error_message returns a static description of an error kind.
error_message :: scan.error_message

// Parser is a streaming N-Triples pull parser over a caller-owned buffer.
// After parser_next returns false, err.kind distinguishes clean end of
// input (.None) from a syntax error. Errors are sticky: once set,
// parser_next keeps returning false.
Parser :: struct {
	using core: st.Parser,
}

// parser_init prepares a parse of source, which must contain the complete
// document and stay valid and unmoved for the parser's lifetime. The
// allocator serves only copy-on-write unescaping.
parser_init :: proc(p: ^Parser, source: []byte, allocator := context.allocator) {
	st.init(&p.core, source, allocator)
}

// parser_destroy releases parser-owned memory (copy-on-write unescapes);
// previously yielded triples become invalid.
parser_destroy :: proc(p: ^Parser) {
	st.destroy(&p.core)
}

// parser_next yields the next triple. The result is valid until the next
// call or parser_destroy. ok is false at end of input or on error; check
// p.err.kind to distinguish (.None means clean end).
parser_next :: proc(p: ^Parser) -> (triple: rdf.Triple, ok: bool) {
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
	if !st.expect_dot(&p.core) {
		return {}, false
	}
	return {subject = subject, predicate = predicate, object = object}, true
}
