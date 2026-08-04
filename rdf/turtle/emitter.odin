package turtle

import "core:io"

import rdf ".."
import ttl "../internal/ttl"

// Prefix is one binding of the caller-supplied prefix map; name is
// without the colon.
Prefix :: ttl.Prefix

// Emitter writes Turtle with minimal prefix-aware abbreviation:
// prefixed names on longest match (only when the remainder re-parses to
// the identical IRI), the 'a' keyword, and ';'/',' grouping of
// consecutive same-subject statements via one-statement lookbehind. An
// empty prefix map yields flat full-IRI output. Triples may be streamed
// straight from a parser — the lookbehind copies what it keeps.
Emitter :: struct {
	using core: ttl.Emitter,
}

// emitter_init writes the '@prefix' header for the supplied bindings.
emitter_init :: proc(
	e: ^Emitter,
	w: io.Writer,
	prefixes: []Prefix = nil,
	allocator := context.allocator,
) -> io.Error {
	return ttl.emitter_init(&e.core, w, prefixes, false, allocator)
}

emitter_destroy :: proc(e: ^Emitter) {
	ttl.emitter_destroy(&e.core)
}

// emit writes one triple, grouping it with the previous statement when
// the subject (and predicate) match.
emit :: proc(e: ^Emitter, t: rdf.Triple) -> io.Error {
	return ttl.emit_grouped(&e.core, t)
}

// emitter_finish closes the open statement; call once after the last
// triple (the emitter remains usable).
emitter_finish :: proc(e: ^Emitter) -> io.Error {
	return ttl.finish(&e.core)
}
