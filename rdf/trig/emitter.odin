package trig

import "core:io"

import rdf ".."
import ttl "../internal/ttl"

// Prefix is one binding of the caller-supplied prefix map; name is
// without the colon.
Prefix :: ttl.Prefix

// Emitter writes TriG with the same minimal abbreviation as the Turtle
// emitter, wrapping consecutive same-graph quads in a graph block;
// default-graph quads emit unwrapped. Blocks are not merged across
// interleavings — each graph change closes the block and opens a new
// one (streaming, no buffering).
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
	return ttl.emitter_init(&e.core, w, prefixes, true, allocator)
}

emitter_destroy :: proc(e: ^Emitter) {
	ttl.emitter_destroy(&e.core)
}

// emit writes one quad, opening/closing graph blocks as the graph
// changes and grouping within a block like the Turtle emitter.
emit :: proc(e: ^Emitter, q: rdf.Quad) -> io.Error {
	ttl.sync_graph(&e.core, q.graph) or_return
	return ttl.emit_grouped(&e.core, q.triple)
}

// emitter_finish closes the open statement and graph block; call once
// after the last quad (the emitter remains usable).
emitter_finish :: proc(e: ^Emitter) -> io.Error {
	return ttl.finish(&e.core)
}
