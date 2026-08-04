// Package statement is the shared statement-level parsing core for the
// line-based formats: term recognition, copy-on-write unescaping, and
// per-statement memory management. rdf/triples and rdf/quads compose
// their grammars from it. Internal to odin-rdf-parser.
package statement

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

import rdf "../.."
import scan "../scanner"

// Parser is the shared parser state the format packages embed. err
// distinguishes clean end of input (.None) from a syntax error after a
// parse procedure returns false; errors are sticky.
Parser :: struct {
	scanner:       scan.Scanner,
	allocator:     runtime.Allocator,
	owned:         [dynamic]string, // unescape allocations for the current statement
	nodes:         [dynamic]^rdf.Triple, // triple-term nodes for the current statement
	lookahead:     scan.Token,
	has_lookahead: bool,
	err:           scan.Error,
}

init :: proc(p: ^Parser, source: []byte, allocator: runtime.Allocator) {
	p^ = {}
	scan.scanner_init(&p.scanner, source)
	p.allocator = allocator
	p.owned.allocator = allocator
	p.nodes.allocator = allocator
}

destroy :: proc(p: ^Parser) {
	free_statement(p)
	delete(p.owned)
	delete(p.nodes)
	p^ = {}
}

// free_statement releases the previous statement's unescape allocations
// and triple-term nodes — call at the start of each pull, enforcing the
// per-statement validity contract.
free_statement :: proc(p: ^Parser) {
	for s in p.owned {
		delete(s, p.allocator)
	}
	clear(&p.owned)
	for node in p.nodes {
		free(node, p.allocator)
	}
	clear(&p.nodes)
}

// parse_subject reads the statement's subject. ok is false at clean end
// of input (err stays .None — no statement started) or on error.
parse_subject :: proc(p: ^Parser) -> (term: rdf.Term, ok: bool) {
	tok, tok_ok := next_token(p)
	if !tok_ok {
		_ = scanner_failed(p)
		return nil, false
	}
	#partial switch tok.kind {
	case .IRI_Ref:
		return iri_term(p, tok)
	case .Blank_Node_Label:
		return rdf.Blank_Node(tok.text), true
	}
	fail_at(p, .Expected_Subject, tok)
	return nil, false
}

parse_predicate :: proc(p: ^Parser) -> (term: rdf.Term, ok: bool) {
	tok, tok_ok := next_token(p)
	if !tok_ok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Predicate)
		}
		return nil, false
	}
	if tok.kind != .IRI_Ref {
		fail_at(p, .Expected_Predicate, tok)
		return nil, false
	}
	return iri_term(p, tok)
}

parse_object :: proc(p: ^Parser) -> (term: rdf.Term, ok: bool) {
	tok, tok_ok := next_token(p)
	if !tok_ok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Object)
		}
		return nil, false
	}
	return parse_object_term(p, tok)
}

// parse_optional_graph_label reads the optional graph label between the
// object and the terminating dot (N-Quads). A directly following '.'
// yields nil — the default graph.
parse_optional_graph_label :: proc(p: ^Parser) -> (graph: rdf.Graph_Label, ok: bool) {
	tok, has := peek_token(p)
	if !has {
		if scanner_failed(p) {
			return nil, false
		}
		return nil, true // EOF; the Dot check reports it
	}
	#partial switch tok.kind {
	case .Dot:
		return nil, true
	case .IRI_Ref:
		_, _ = next_token(p)
		iri, iri_ok := iri_term(p, tok)
		if !iri_ok {
			return nil, false
		}
		return iri.(rdf.IRI), true
	case .Blank_Node_Label:
		_, _ = next_token(p)
		return rdf.Blank_Node(tok.text), true
	}
	fail_at(p, .Invalid_Graph_Label, tok)
	return nil, false
}

expect_dot :: proc(p: ^Parser) -> bool {
	tok, tok_ok := next_token(p)
	if !tok_ok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Dot)
		}
		return false
	}
	if tok.kind != .Dot {
		fail_at(p, .Expected_Dot, tok)
		return false
	}
	return true
}

@(private)
parse_object_term :: proc(p: ^Parser, tok: scan.Token) -> (term: rdf.Term, ok: bool) {
	#partial switch tok.kind {
	case .IRI_Ref:
		return iri_term(p, tok)
	case .Blank_Node_Label:
		return rdf.Blank_Node(tok.text), true
	case .String_Literal:
		return parse_literal(p, tok)
	case .Triple_Term_Open:
		return parse_triple_term(p)
	}
	fail_at(p, .Expected_Object, tok)
	return nil, false
}

@(private)
parse_literal :: proc(p: ^Parser, tok: scan.Token) -> (term: rdf.Term, ok: bool) {
	lexical := maybe_unescape(p, tok)
	peeked, has := peek_token(p)
	if !has {
		if scanner_failed(p) {
			return nil, false
		}
		return rdf.literal_plain(lexical), true // EOF; the Dot check reports it
	}
	#partial switch peeked.kind {
	case .Lang_Tag:
		_, _ = next_token(p)
		lang := peeked.text
		direction := rdf.Direction.None
		if idx := strings.index(lang, "--"); idx >= 0 {
			switch lang[idx + 2:] {
			case "ltr":
				direction = .LTR
			case "rtl":
				direction = .RTL
			case:
				fail_at(p, .Invalid_Direction, peeked)
				return nil, false
			}
			lang = lang[:idx]
		}
		if direction == .None {
			return rdf.literal_lang(lexical, lang), true
		}
		return rdf.literal_dir_lang(lexical, lang, direction), true
	case .Datatype_Marker:
		_, _ = next_token(p)
		dtok, dok := next_token(p)
		if !dok {
			if !scanner_failed(p) {
				fail_here(p, .Expected_Datatype)
			}
			return nil, false
		}
		if dtok.kind != .IRI_Ref {
			fail_at(p, .Expected_Datatype, dtok)
			return nil, false
		}
		dt_term, dt_ok := iri_term(p, dtok)
		if !dt_ok {
			return nil, false
		}
		dt := dt_term.(rdf.IRI)
		// RDF 1.2 reserves these datatypes for language-tag syntax
		// (W3C tests ntriples-langdir-bad-3/-5).
		if dt == rdf.RDF_LANG_STRING || dt == rdf.RDF_DIR_LANG_STRING {
			fail_at(p, .Reserved_Datatype, dtok)
			return nil, false
		}
		// Built directly, not via rdf.literal_typed, whose assert guards
		// against the reserved datatypes already rejected above.
		return rdf.Literal{lexical = lexical, datatype = dt}, true
	}
	return rdf.literal_plain(lexical), true
}

@(private)
parse_triple_term :: proc(p: ^Parser) -> (term: rdf.Term, ok: bool) {
	stok, sok := next_token(p)
	if !sok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Subject)
		}
		return nil, false
	}
	subject: rdf.Term
	#partial switch stok.kind {
	case .IRI_Ref:
		subject_ok: bool
		subject, subject_ok = iri_term(p, stok)
		if !subject_ok {
			return nil, false
		}
	case .Blank_Node_Label:
		subject = rdf.Blank_Node(stok.text)
	case:
		fail_at(p, .Expected_Subject, stok)
		return nil, false
	}

	predicate, pok := parse_predicate(p)
	if !pok {
		return nil, false
	}

	object, ook := parse_object(p)
	if !ook {
		return nil, false
	}

	ctok, cok := next_token(p)
	if !cok {
		if !scanner_failed(p) {
			fail_here(p, .Unclosed_Triple_Term)
		}
		return nil, false
	}
	if ctok.kind != .Triple_Term_Close {
		fail_at(p, .Unclosed_Triple_Term, ctok)
		return nil, false
	}

	node := new(rdf.Triple, p.allocator)
	node^ = {
		subject   = subject,
		predicate = predicate,
		object    = object,
	}
	append(&p.nodes, node)
	return node, true
}

@(private)
iri_term :: proc(p: ^Parser, tok: scan.Token) -> (term: rdf.Term, ok: bool) {
	s := maybe_unescape(p, tok)
	if !is_absolute_iri(s) {
		fail_at(p, .Relative_IRI, tok)
		return nil, false
	}
	return rdf.IRI(s), true
}

// is_absolute_iri checks for a leading scheme ("alpha (alnum|+|-|.)* :"),
// the same level of validation conforming N-Triples parsers apply — full
// RFC 3987 validation is out of scope (vision non-goal).
@(private)
is_absolute_iri :: proc(s: string) -> bool {
	if len(s) == 0 {
		return false
	}
	first := s[0]
	if !(first >= 'a' && first <= 'z' || first >= 'A' && first <= 'Z') {
		return false
	}
	for i in 1 ..< len(s) {
		switch c := s[i]; c {
		case ':':
			return true
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '+', '-', '.':
			// still in the scheme
		case:
			return false
		}
	}
	return false
}

// maybe_unescape returns the token text as a borrowed slice when it has
// no escapes (the common case, no allocation), and otherwise an unescaped
// copy owned by the parser until the next statement.
@(private)
maybe_unescape :: proc(p: ^Parser, tok: scan.Token) -> string {
	if !tok.has_escape {
		return tok.text
	}
	// The scanner validated every escape, so decoding cannot fail. The
	// decoded form never exceeds the escaped form, so the buffer never
	// reallocates and the string can be freed by pointer.
	b := make([dynamic]byte, 0, len(tok.text), p.allocator)
	s := tok.text
	i := 0
	for i < len(s) {
		if s[i] != '\\' {
			append(&b, s[i])
			i += 1
			continue
		}
		i += 1
		switch s[i] {
		case 't':
			append(&b, '\t')
			i += 1
		case 'b':
			append(&b, '\b')
			i += 1
		case 'n':
			append(&b, '\n')
			i += 1
		case 'r':
			append(&b, '\r')
			i += 1
		case 'f':
			append(&b, '\f')
			i += 1
		case '"':
			append(&b, '"')
			i += 1
		case '\'':
			append(&b, '\'')
			i += 1
		case '\\':
			append(&b, '\\')
			i += 1
		case 'u':
			encoded, n := utf8.encode_rune(rune(decode_hex(s[i + 1:i + 5])))
			append(&b, ..encoded[:n])
			i += 5
		case 'U':
			encoded, n := utf8.encode_rune(rune(decode_hex(s[i + 1:i + 9])))
			append(&b, ..encoded[:n])
			i += 9
		}
	}
	result := string(b[:])
	append(&p.owned, result)
	return result
}

@(private)
decode_hex :: proc(s: string) -> (value: u32) {
	for c in transmute([]byte)s {
		value <<= 4
		switch c {
		case '0' ..= '9':
			value |= u32(c - '0')
		case 'a' ..= 'f':
			value |= u32(c - 'a' + 10)
		case 'A' ..= 'F':
			value |= u32(c - 'A' + 10)
		}
	}
	return value
}

next_token :: proc(p: ^Parser) -> (scan.Token, bool) {
	if p.has_lookahead {
		p.has_lookahead = false
		return p.lookahead, true
	}
	return scan.scanner_next(&p.scanner)
}

peek_token :: proc(p: ^Parser) -> (scan.Token, bool) {
	if !p.has_lookahead {
		tok, ok := scan.scanner_next(&p.scanner)
		if !ok {
			return {}, false
		}
		p.lookahead = tok
		p.has_lookahead = true
	}
	return p.lookahead, true
}

// scanner_failed promotes a scanner error to the parser and reports
// whether one occurred; a clean end of input is not a failure.
scanner_failed :: proc(p: ^Parser) -> bool {
	if p.scanner.err.kind != .None {
		p.err = p.scanner.err
		return true
	}
	return false
}

fail_at :: proc(p: ^Parser, kind: scan.Error_Kind, tok: scan.Token) {
	p.err = {
		kind   = kind,
		offset = tok.offset,
		line   = tok.line,
		column = tok.column,
	}
}

// fail_here reports an error at the current scanner position (end of
// input reached while a statement was incomplete).
fail_here :: proc(p: ^Parser, kind: scan.Error_Kind) {
	p.err = {
		kind   = kind,
		offset = p.scanner.pos,
		line   = p.scanner.line,
		column = p.scanner.pos - p.scanner.line_start + 1,
	}
}
