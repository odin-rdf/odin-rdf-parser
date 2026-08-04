package triples

import "core:io"

import rdf ".."
import em "../internal/emit"

// emit writes one triple as an N-Triples statement line ("s p o .\n").
// Escaping is the exact inverse of the parser's unescaping; emission
// never allocates.
emit :: proc(w: io.Writer, t: rdf.Triple) -> io.Error {
	em.write_triple(w, t) or_return
	_, err := io.write_string(w, " .\n")
	return err
}

// emit_all writes each triple in order as an N-Triples document.
emit_all :: proc(w: io.Writer, ts: []rdf.Triple) -> io.Error {
	for t in ts {
		emit(w, t) or_return
	}
	return nil
}
