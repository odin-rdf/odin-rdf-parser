package quads

import "core:io"

import rdf ".."
import em "../internal/emit"

// emit writes one quad as an N-Quads statement line; a nil graph label
// (default graph) emits no label. Escaping is the exact inverse of the
// parser's unescaping; emission never allocates.
emit :: proc(w: io.Writer, q: rdf.Quad) -> io.Error {
	em.write_triple(w, q.triple) or_return
	if q.graph != nil {
		io.write_byte(w, ' ') or_return
		em.write_graph_label(w, q.graph) or_return
	}
	_, err := io.write_string(w, " .\n")
	return err
}

// emit_all writes each quad in order as an N-Quads document.
emit_all :: proc(w: io.Writer, qs: []rdf.Quad) -> io.Error {
	for q in qs {
		emit(w, q) or_return
	}
	return nil
}
