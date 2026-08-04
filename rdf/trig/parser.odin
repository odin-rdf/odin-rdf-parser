// Package trig parses the W3C TriG format (RDF 1.2): the full Turtle
// grammar plus named graph blocks, yielding quads.
//
// It is a thin layer over the same parser core as rdf/turtle
// (rdf/internal/ttl) — the memory contract is identical: intern-table
// strings live until parser_destroy, everything else in a yielded quad
// is valid only until its statement has been fully drained (ADR
// RDF-A-0001, RDF-I-0003).
package trig

import rdf ".."
import scan "../internal/scanner"
import ttl "../internal/ttl"

// Error and Error_Kind are shared with every format package.
Error :: scan.Error
Error_Kind :: scan.Error_Kind
// error_message returns a static description of an error kind.
error_message :: scan.error_message

// Parser is a streaming TriG pull parser over a caller-owned buffer.
// After parser_next returns false, err.kind distinguishes clean end of
// input (.None) from a syntax error. Errors are sticky.
Parser :: struct {
	using core: ttl.Parser,
}

// parser_init prepares a parse; base is the IRI against which relative
// references resolve (typically the document's location).
parser_init :: proc(p: ^Parser, source: []byte, base := "", allocator := context.allocator) {
	ttl.init(&p.core, source, base, allocator)
	p.core.trig_mode = true
}

parser_destroy :: proc(p: ^Parser) {
	ttl.destroy(&p.core)
}

// parser_next yields the next quad; statements outside graph blocks
// yield a nil Graph_Label (the default graph). ok is false at end of
// input or on error; check p.err.kind to distinguish (.None means
// clean end).
parser_next :: proc(p: ^Parser) -> (quad: rdf.Quad, ok: bool) {
	t, tok := ttl.next_triple(&p.core)
	if !tok {
		return {}, false
	}
	return rdf.Quad{triple = t, graph = p.core.current_graph}, true
}
