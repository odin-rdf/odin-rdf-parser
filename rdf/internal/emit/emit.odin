// Package emit is the shared character-level emission core for the
// line-based formats: term serialization and the escaping that is the
// exact inverse of the parsers' unescaping. Internal to odin-rdf-parser.
//
// Emission never allocates; every write goes straight to the io.Writer.
// Callers are responsible for grammar-valid statements — emitting a nil
// Term writes nothing and produces invalid output.
package emit

import "core:io"

import rdf "../.."

// write_triple writes "subject predicate object" without a terminating
// dot, so the format packages control statement framing.
write_triple :: proc(w: io.Writer, t: rdf.Triple) -> io.Error {
	write_term(w, t.subject) or_return
	io.write_byte(w, ' ') or_return
	write_term(w, t.predicate) or_return
	io.write_byte(w, ' ') or_return
	write_term(w, t.object) or_return
	return nil
}

write_term :: proc(w: io.Writer, term: rdf.Term) -> io.Error {
	switch v in term {
	case rdf.IRI:
		write_iri(w, v) or_return
	case rdf.Blank_Node:
		ws(w, "_:") or_return
		ws(w, string(v)) or_return
	case rdf.Literal:
		io.write_byte(w, '"') or_return
		write_escaped(w, v.lexical) or_return
		io.write_byte(w, '"') or_return
		switch v.datatype {
		case rdf.XSD_STRING, rdf.IRI(""):
			// Plain literal: xsd:string is implicit (canonical form). An
			// empty datatype only occurs in hand-built values; treat as plain.
		case rdf.RDF_LANG_STRING:
			io.write_byte(w, '@') or_return
			ws(w, v.language) or_return
		case rdf.RDF_DIR_LANG_STRING:
			io.write_byte(w, '@') or_return
			ws(w, v.language) or_return
			ws(w, "--rtl" if v.direction == .RTL else "--ltr") or_return
		case:
			ws(w, "^^") or_return
			write_iri(w, v.datatype) or_return
		}
	case ^rdf.Triple:
		ws(w, "<<( ") or_return
		write_triple(w, v^) or_return
		ws(w, " )>>") or_return
	}
	return nil
}

// write_graph_label writes the label with no surrounding spacing; the
// caller decides framing. A nil label (default graph) writes nothing.
write_graph_label :: proc(w: io.Writer, g: rdf.Graph_Label) -> io.Error {
	switch v in g {
	case rdf.IRI:
		write_iri(w, v) or_return
	case rdf.Blank_Node:
		ws(w, "_:") or_return
		ws(w, string(v)) or_return
	}
	return nil
}

// write_iri and write_escaped are shared with the Turtle-family
// emitters (rdf/internal/ttl), which add prefix abbreviation on top.
write_iri :: proc(w: io.Writer, iri: rdf.IRI) -> io.Error {
	io.write_byte(w, '<') or_return
	// IRIREF forbids control characters, space, and <>"{}|^`\ — a valid
	// IRI contains none of them, but escape defensively so the output is
	// always grammatically valid.
	s := string(iri)
	start := 0
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		needs_escape: bool
		switch c {
		case '<', '"', '{', '}', '|', '^', '`', '\\':
			needs_escape = true
		case:
			needs_escape = c <= 0x20
		}
		if needs_escape {
			ws(w, s[start:i]) or_return
			write_u_escape(w, c) or_return
			start = i + 1
		}
	}
	ws(w, s[start:]) or_return
	io.write_byte(w, '>') or_return
	return nil
}

// write_escaped writes a literal's lexical form with the minimal
// mandatory escaping: named ECHARs for the common control characters and
// the delimiter/backslash, \u00XX for the remaining control characters.
write_escaped :: proc(w: io.Writer, s: string) -> io.Error {
	start := 0
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		esc: string
		switch c {
		case '"':
			esc = "\\\""
		case '\\':
			esc = "\\\\"
		case '\n':
			esc = "\\n"
		case '\r':
			esc = "\\r"
		case '\t':
			esc = "\\t"
		case '\b':
			esc = "\\b"
		case '\f':
			esc = "\\f"
		case:
			if c >= 0x20 {
				continue
			}
			ws(w, s[start:i]) or_return
			write_u_escape(w, c) or_return
			start = i + 1
			continue
		}
		ws(w, s[start:i]) or_return
		ws(w, esc) or_return
		start = i + 1
	}
	ws(w, s[start:]) or_return
	return nil
}

@(private)
write_u_escape :: proc(w: io.Writer, c: byte) -> io.Error {
	hex := "0123456789ABCDEF"
	buf := [6]byte{'\\', 'u', '0', '0', hex[c >> 4], hex[c & 0xF]}
	ws(w, string(buf[:])) or_return
	return nil
}

@(private)
ws :: proc(w: io.Writer, s: string) -> io.Error {
	_, err := io.write_string(w, s)
	return err
}
