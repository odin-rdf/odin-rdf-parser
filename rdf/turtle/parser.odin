// Package turtle parses the W3C Turtle format (RDF 1.2), including
// RDF-star.
//
// Parsing is streaming with the RDF-I-0003 memory contract: prefix
// expansions, resolved IRIs, and synthesized blank-node labels are
// owned by the parser's intern table and stay valid until
// parser_destroy; everything else in a yielded triple is valid only
// until the statement it came from has been fully drained (one Turtle
// statement can yield many triples). Keep statements with rdf.clone or
// an rdf.Intern_Table (ADR RDF-A-0001).
package turtle

import rdf ".."
import scan "../internal/scanner"
import ttl "../internal/ttl"

// Error and Error_Kind are shared with every format package.
Error :: scan.Error
Error_Kind :: scan.Error_Kind
// error_message returns a static description of an error kind.
error_message :: scan.error_message

// Parser is a streaming Turtle pull parser over a caller-owned buffer.
// After parser_next returns false, err.kind distinguishes clean end of
// input (.None) from a syntax error. Errors are sticky.
Parser :: struct {
	using core: ttl.Parser,
}

// parser_init prepares a parse. base is the IRI against which relative
// references resolve (typically the document's location); with an empty
// base, a document that uses relative IRIs before establishing a @base
// is an error.
parser_init :: proc(p: ^Parser, source: []byte, base := "", allocator := context.allocator) {
	ttl.init(&p.core, source, base, allocator)
}

parser_destroy :: proc(p: ^Parser) {
	ttl.destroy(&p.core)
}

// parser_next yields the next triple; see the package documentation for
// the validity contract. ok is false at end of input or on error; check
// p.err.kind to distinguish (.None means clean end).
parser_next :: proc(p: ^Parser) -> (triple: rdf.Triple, ok: bool) {
	return ttl.next_triple(&p.core)
}
