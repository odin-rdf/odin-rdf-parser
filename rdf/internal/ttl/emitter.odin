// Turtle-family emitter core: prefix-aware, minimal abbreviation per
// the RDF-I-0003 design decision — caller-supplied prefix map, the 'a'
// keyword, and ';'/',' grouping of consecutive same-subject statements
// via one-statement lookbehind. No reordering, no buffering engine; an
// empty prefix map degrades to flat full-IRI output.
//
// The lookbehind state is copied into emitter-owned buffers (capacity
// reused), so callers may stream triples straight from a parser whose
// terms die with each statement.
package ttl

import "base:runtime"
import "core:io"
import "core:strings"
import "core:unicode/utf8"

import rdf "../.."
import em "../emit"

// Prefix is one caller-supplied prefix binding; name is without the
// colon. Bindings with an empty iri are ignored.
Prefix :: struct {
	name: string,
	iri:  string,
}

@(private)
Prev_Graph :: enum u8 {
	Default,
	IRI,
	Blank,
}

Emitter :: struct {
	w:          io.Writer,
	prefixes:   []Prefix,
	trig:       bool,
	started:    bool, // a statement is open and needs its ' .' close
	in_block:   bool,
	prev_subj:  [dynamic]byte,
	subj_blank: bool,
	prev_pred:  [dynamic]byte,
	prev_graph: [dynamic]byte,
	graph_kind: Prev_Graph,
}

// emitter_init writes the '@prefix' header for every supplied binding
// (all of them, used or not — deterministic and streaming-friendly).
emitter_init :: proc(
	e: ^Emitter,
	w: io.Writer,
	prefixes: []Prefix,
	trig: bool,
	allocator: runtime.Allocator,
) -> io.Error {
	e^ = {
		w        = w,
		prefixes = prefixes,
		trig     = trig,
	}
	e.prev_subj.allocator = allocator
	e.prev_pred.allocator = allocator
	e.prev_graph.allocator = allocator
	for p in prefixes {
		if len(p.iri) == 0 {
			continue
		}
		io.write_string(e.w, "@prefix ") or_return
		io.write_string(e.w, p.name) or_return
		io.write_string(e.w, ": ") or_return
		em.write_iri(e.w, rdf.IRI(p.iri)) or_return
		io.write_string(e.w, " .\n") or_return
	}
	return nil
}

emitter_destroy :: proc(e: ^Emitter) {
	delete(e.prev_subj)
	delete(e.prev_pred)
	delete(e.prev_graph)
	e^ = {}
}

// emit_grouped writes one statement with lookbehind grouping. The trig
// layer calls sync_graph first; the turtle layer never opens a block.
emit_grouped :: proc(e: ^Emitter, t: rdf.Triple) -> io.Error {
	same_subj := e.started && subject_matches(e, t.subject)
	if same_subj && predicate_matches(e, t.predicate) {
		io.write_string(e.w, " , ") or_return
		write_object(e, t.object) or_return
		return nil
	}
	if same_subj {
		io.write_string(e.w, " ;\n") or_return
		io.write_string(e.w, e.in_block ? "      " : "    ") or_return
		write_predicate(e, t.predicate) or_return
		io.write_byte(e.w, ' ') or_return
		write_object(e, t.object) or_return
		save_predicate(e, t.predicate)
		return nil
	}
	if e.started {
		io.write_string(e.w, " .\n") or_return
	}
	if e.in_block {
		io.write_string(e.w, "  ") or_return
	}
	write_subject(e, t.subject) or_return
	io.write_byte(e.w, ' ') or_return
	write_predicate(e, t.predicate) or_return
	io.write_byte(e.w, ' ') or_return
	write_object(e, t.object) or_return
	save_subject(e, t.subject)
	save_predicate(e, t.predicate)
	e.started = true
	return nil
}

// sync_graph closes and opens graph blocks so the coming statement
// lands in the given graph; the default graph emits unwrapped.
sync_graph :: proc(e: ^Emitter, g: rdf.Graph_Label) -> io.Error {
	if graph_matches(e, g) {
		return nil
	}
	if e.started {
		io.write_string(e.w, " .\n") or_return
		e.started = false
	}
	if e.in_block {
		io.write_string(e.w, "}\n") or_return
		e.in_block = false
	}
	clear(&e.prev_graph)
	switch v in g {
	case rdf.IRI:
		e.graph_kind = .IRI
		append(&e.prev_graph, string(v))
		write_iri_abbrev(e, v) or_return
		io.write_string(e.w, " {\n") or_return
		e.in_block = true
	case rdf.Blank_Node:
		e.graph_kind = .Blank
		append(&e.prev_graph, string(v))
		io.write_string(e.w, "_:") or_return
		io.write_string(e.w, string(v)) or_return
		io.write_string(e.w, " {\n") or_return
		e.in_block = true
	case:
		e.graph_kind = .Default
	}
	return nil
}

// finish closes the open statement (and graph block); the emitter can
// keep emitting afterwards.
finish :: proc(e: ^Emitter) -> io.Error {
	if e.started {
		io.write_string(e.w, " .\n") or_return
		e.started = false
	}
	if e.in_block {
		io.write_string(e.w, "}\n") or_return
		e.in_block = false
		e.graph_kind = .Default
		clear(&e.prev_graph)
	}
	return nil
}

@(private)
subject_matches :: proc(e: ^Emitter, term: rdf.Term) -> bool {
	#partial switch v in term {
	case rdf.IRI:
		return !e.subj_blank && string(v) == string(e.prev_subj[:])
	case rdf.Blank_Node:
		return e.subj_blank && string(v) == string(e.prev_subj[:])
	}
	return false
}

@(private)
predicate_matches :: proc(e: ^Emitter, term: rdf.Term) -> bool {
	if v, is_iri := term.(rdf.IRI); is_iri {
		return string(v) == string(e.prev_pred[:])
	}
	return false
}

@(private)
graph_matches :: proc(e: ^Emitter, g: rdf.Graph_Label) -> bool {
	switch v in g {
	case rdf.IRI:
		return e.graph_kind == .IRI && string(v) == string(e.prev_graph[:])
	case rdf.Blank_Node:
		return e.graph_kind == .Blank && string(v) == string(e.prev_graph[:])
	}
	return e.graph_kind == .Default
}

@(private)
save_subject :: proc(e: ^Emitter, term: rdf.Term) {
	clear(&e.prev_subj)
	#partial switch v in term {
	case rdf.IRI:
		e.subj_blank = false
		append(&e.prev_subj, string(v))
	case rdf.Blank_Node:
		e.subj_blank = true
		append(&e.prev_subj, string(v))
	case:
		// Grouping never matches non-IRI/blank subjects; poison the
		// buffer so the next statement starts fresh.
		e.subj_blank = false
	}
}

@(private)
save_predicate :: proc(e: ^Emitter, term: rdf.Term) {
	clear(&e.prev_pred)
	if v, is_iri := term.(rdf.IRI); is_iri {
		append(&e.prev_pred, string(v))
	}
}

@(private)
write_subject :: proc(e: ^Emitter, term: rdf.Term) -> io.Error {
	return write_term_abbrev(e, term)
}

@(private)
write_predicate :: proc(e: ^Emitter, term: rdf.Term) -> io.Error {
	if v, is_iri := term.(rdf.IRI); is_iri && v == rdf.RDF_TYPE {
		return io.write_byte(e.w, 'a')
	}
	return write_term_abbrev(e, term)
}

@(private)
write_object :: proc(e: ^Emitter, term: rdf.Term) -> io.Error {
	return write_term_abbrev(e, term)
}

@(private)
write_term_abbrev :: proc(e: ^Emitter, term: rdf.Term) -> io.Error {
	switch v in term {
	case rdf.IRI:
		return write_iri_abbrev(e, v)
	case rdf.Blank_Node:
		io.write_string(e.w, "_:") or_return
		_, err := io.write_string(e.w, string(v))
		return err
	case rdf.Literal:
		io.write_byte(e.w, '"') or_return
		em.write_escaped(e.w, v.lexical) or_return
		io.write_byte(e.w, '"') or_return
		switch v.datatype {
		case rdf.XSD_STRING, rdf.IRI(""):
		// plain literal: implicit xsd:string
		case rdf.RDF_LANG_STRING:
			io.write_byte(e.w, '@') or_return
			io.write_string(e.w, v.language) or_return
		case rdf.RDF_DIR_LANG_STRING:
			io.write_byte(e.w, '@') or_return
			io.write_string(e.w, v.language) or_return
			io.write_string(e.w, "--rtl" if v.direction == .RTL else "--ltr") or_return
		case:
			io.write_string(e.w, "^^") or_return
			write_iri_abbrev(e, v.datatype) or_return
		}
		return nil
	case ^rdf.Triple:
		io.write_string(e.w, "<<( ") or_return
		write_term_abbrev(e, v.subject) or_return
		io.write_byte(e.w, ' ') or_return
		write_predicate(e, v.predicate) or_return
		io.write_byte(e.w, ' ') or_return
		write_term_abbrev(e, v.object) or_return
		_, err := io.write_string(e.w, " )>>")
		return err
	}
	return nil
}

// write_iri_abbrev writes the longest-prefix abbreviation when the
// remainder is an emittable PN_LOCAL (correctness bar: the prefixed
// name must re-parse to the identical IRI), and the full '<>' form
// otherwise.
@(private)
write_iri_abbrev :: proc(e: ^Emitter, iri: rdf.IRI) -> io.Error {
	s := string(iri)
	best := -1
	best_len := -1
	for p, i in e.prefixes {
		if len(p.iri) == 0 || len(p.iri) <= best_len {
			continue
		}
		if strings.has_prefix(s, p.iri) && local_emittable(s[len(p.iri):]) {
			best = i
			best_len = len(p.iri)
		}
	}
	if best < 0 {
		return em.write_iri(e.w, iri)
	}
	io.write_string(e.w, e.prefixes[best].name) or_return
	io.write_byte(e.w, ':') or_return
	return write_local(e.w, s[best_len:])
}

// local_emittable reports whether s can be written as a PN_LOCAL —
// possibly with PN_LOCAL_ESC escaping — such that parsing recovers s
// exactly. The empty local is valid (the namespace itself).
@(private)
local_emittable :: proc(s: string) -> bool {
	i := 0
	first := true
	for i < len(s) {
		c := s[i]
		if c == '%' || c == ':' || is_pn_local_esc(c) {
			// ':' is raw; '%' is raw with a valid hex pair and '\%'
			// otherwise; the escape set is always writable.
			i += 1
			first = false
			continue
		}
		r, n := decode_rune_in(s, i)
		if n == 0 {
			return false
		}
		if first {
			if !(is_pn_chars_u(r) || is_digit_rune(r)) {
				return false
			}
		} else if !is_pn_chars(r) {
			return false
		}
		i += n
		first = false
	}
	return true
}

// write_local writes a PN_LOCAL validated by local_emittable: dots stay
// raw in the interior and are escaped at the edges, '%' stays raw only
// before a hex pair, and the remaining PN_LOCAL_ESC characters (minus
// '_' and '-', which are PN_CHARS) are always escaped.
@(private)
write_local :: proc(w: io.Writer, s: string) -> io.Error {
	start := 0
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		needs_escape: bool
		switch {
		case c == '.':
			needs_escape = i == 0 || i == len(s) - 1
		case c == '%':
			needs_escape = !(i + 2 < len(s) &&
				is_hex_byte(s[i + 1]) && is_hex_byte(s[i + 2]))
		case c == '_' || c == '-' || c == ':':
			needs_escape = false
		case:
			needs_escape = is_pn_local_esc(c)
		}
		if needs_escape {
			io.write_string(w, s[start:i]) or_return
			io.write_byte(w, '\\') or_return
			start = i
		}
	}
	_, err := io.write_string(w, s[start:])
	return err
}

@(private)
is_hex_byte :: proc(c: byte) -> bool {
	switch c {
	case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
		return true
	}
	return false
}

@(private)
decode_rune_in :: proc(s: string, at: int) -> (r: rune, n: int) {
	c := s[at]
	if c < 0x80 {
		return rune(c), 1
	}
	r, n = utf8.decode_rune_in_string(s[at:])
	if r == utf8.RUNE_ERROR && n <= 1 {
		return 0, 0
	}
	return r, n
}
