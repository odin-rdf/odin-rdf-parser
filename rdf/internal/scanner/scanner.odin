// Package scanner is the shared tokenizer for the line-based RDF formats
// (N-Triples, N-Quads). It is internal to odin-rdf-parser — not part of
// the public API, no compatibility promises.
//
// Tokens borrow from the caller-owned source buffer (ADR RDF-A-0001);
// scanning never allocates.
package scanner

Scanner :: struct {
	source:     []byte,
	pos:        int,
	line:       int, // 1-based
	line_start: int, // byte offset where the current line begins
	err:        Error,
}

scanner_init :: proc(s: ^Scanner, source: []byte) {
	s^ = {
		source = source,
		line   = 1,
	}
}

// scanner_next returns the next token. ok is false at end of input or on
// error; s.err.kind distinguishes the two (.None means clean end).
scanner_next :: proc(s: ^Scanner) -> (tok: Token, ok: bool) {
	if s.err.kind != .None {
		return {}, false
	}
	skip_whitespace(s)
	if s.pos >= len(s.source) {
		return {}, false
	}

	start := s.pos
	tok = Token {
		offset = start,
		line   = s.line,
		column = start - s.line_start + 1,
	}

	switch s.source[s.pos] {
	case '<':
		if s.pos + 2 < len(s.source) && s.source[s.pos + 1] == '<' && s.source[s.pos + 2] == '(' {
			s.pos += 3
			tok.kind = .Triple_Term_Open
			return tok, true
		}
		s.pos += 1
		content_start := s.pos
		for {
			if s.pos >= len(s.source) {
				set_error(s, .Unterminated_IRI, start)
				return {}, false
			}
			c := s.source[s.pos]
			switch {
			case c == '>':
				tok.kind = .IRI_Ref
				tok.text = string(s.source[content_start:s.pos])
				s.pos += 1
				return tok, true
			case c == '\\':
				tok.has_escape = true
				if !scan_iri_escape(s) {
					return {}, false
				}
			case c <= 0x20 || c == '<' || c == '"' || c == '{' || c == '}' || c == '|' || c == '^' || c == '`':
				set_error(s, .Invalid_IRI_Character, s.pos)
				return {}, false
			case:
				s.pos += 1
			}
		}

	case '"':
		s.pos += 1
		content_start := s.pos
		for {
			if s.pos >= len(s.source) {
				set_error(s, .Unterminated_String, start)
				return {}, false
			}
			switch s.source[s.pos] {
			case '"':
				tok.kind = .String_Literal
				tok.text = string(s.source[content_start:s.pos])
				s.pos += 1
				return tok, true
			case '\\':
				tok.has_escape = true
				if !scan_string_escape(s) {
					return {}, false
				}
			case '\n', '\r':
				set_error(s, .Invalid_String_Character, s.pos)
				return {}, false
			case:
				s.pos += 1
			}
		}

	case '_':
		if s.pos + 1 >= len(s.source) || s.source[s.pos + 1] != ':' {
			set_error(s, .Invalid_Blank_Node_Label, start)
			return {}, false
		}
		s.pos += 2
		content_start := s.pos
		if s.pos >= len(s.source) || !is_label_start(s.source[s.pos]) {
			set_error(s, .Invalid_Blank_Node_Label, start)
			return {}, false
		}
		s.pos += 1
		for s.pos < len(s.source) {
			c := s.source[s.pos]
			if c == '.' {
				// A dot is part of the label only when followed by another
				// label character; otherwise it terminates the statement.
				if s.pos + 1 < len(s.source) && is_label_char(s.source[s.pos + 1]) {
					s.pos += 1
					continue
				}
				break
			}
			if !is_label_char(c) {
				break
			}
			s.pos += 1
		}
		tok.kind = .Blank_Node_Label
		tok.text = string(s.source[content_start:s.pos])
		return tok, true

	case '@':
		s.pos += 1
		content_start := s.pos
		if s.pos >= len(s.source) || !is_alpha(s.source[s.pos]) {
			set_error(s, .Invalid_Lang_Tag, start)
			return {}, false
		}
		for s.pos < len(s.source) && is_alpha(s.source[s.pos]) {
			s.pos += 1
		}
		subtags: for s.pos < len(s.source) && s.source[s.pos] == '-' {
			if s.pos + 1 < len(s.source) && s.source[s.pos + 1] == '-' {
				// RDF 1.2 base direction suffix: '--' [a-zA-Z]+
				s.pos += 2
				dir_start := s.pos
				for s.pos < len(s.source) && is_alpha(s.source[s.pos]) {
					s.pos += 1
				}
				if s.pos == dir_start {
					set_error(s, .Invalid_Lang_Tag, start)
					return {}, false
				}
				break subtags
			}
			s.pos += 1
			seg_start := s.pos
			for s.pos < len(s.source) && is_alnum(s.source[s.pos]) {
				s.pos += 1
			}
			if s.pos == seg_start {
				set_error(s, .Invalid_Lang_Tag, start)
				return {}, false
			}
		}
		tok.kind = .Lang_Tag
		tok.text = string(s.source[content_start:s.pos])
		return tok, true

	case '^':
		if s.pos + 1 < len(s.source) && s.source[s.pos + 1] == '^' {
			s.pos += 2
			tok.kind = .Datatype_Marker
			return tok, true
		}
		set_error(s, .Unexpected_Character, start)
		return {}, false

	case '.':
		s.pos += 1
		tok.kind = .Dot
		return tok, true

	case ')':
		if s.pos + 2 < len(s.source) && s.source[s.pos + 1] == '>' && s.source[s.pos + 2] == '>' {
			s.pos += 3
			tok.kind = .Triple_Term_Close
			return tok, true
		}
		set_error(s, .Unexpected_Character, start)
		return {}, false
	}

	set_error(s, .Unexpected_Character, start)
	return {}, false
}

@(private)
set_error :: proc(s: ^Scanner, kind: Error_Kind, offset: int) {
	s.err = Error {
		kind   = kind,
		offset = offset,
		line   = s.line,
		column = offset - s.line_start + 1,
	}
}

@(private)
skip_whitespace :: proc(s: ^Scanner) {
	for s.pos < len(s.source) {
		switch s.source[s.pos] {
		case ' ', '\t', '\r':
			s.pos += 1
		case '\n':
			s.pos += 1
			s.line += 1
			s.line_start = s.pos
		case '#':
			for s.pos < len(s.source) && s.source[s.pos] != '\n' {
				s.pos += 1
			}
		case:
			return
		}
	}
}

// scan_iri_escape validates a UCHAR escape (\uXXXX or \UXXXXXXXX), the
// only escapes IRIREF permits. s.pos is at the backslash on entry.
@(private)
scan_iri_escape :: proc(s: ^Scanner) -> bool {
	esc := s.pos
	s.pos += 1
	if s.pos < len(s.source) {
		switch s.source[s.pos] {
		case 'u':
			s.pos += 1
			return scan_hex(s, 4, esc)
		case 'U':
			s.pos += 1
			return scan_hex(s, 8, esc)
		}
	}
	set_error(s, .Invalid_Escape, esc)
	return false
}

// scan_string_escape validates an ECHAR or UCHAR escape inside a string
// literal. s.pos is at the backslash on entry.
@(private)
scan_string_escape :: proc(s: ^Scanner) -> bool {
	esc := s.pos
	s.pos += 1
	if s.pos < len(s.source) {
		switch s.source[s.pos] {
		case 't', 'b', 'n', 'r', 'f', '"', '\'', '\\':
			s.pos += 1
			return true
		case 'u':
			s.pos += 1
			return scan_hex(s, 4, esc)
		case 'U':
			s.pos += 1
			return scan_hex(s, 8, esc)
		}
	}
	set_error(s, .Invalid_Escape, esc)
	return false
}

@(private)
scan_hex :: proc(s: ^Scanner, n: int, esc_offset: int) -> bool {
	for _ in 0 ..< n {
		if s.pos >= len(s.source) || !is_hex_digit(s.source[s.pos]) {
			set_error(s, .Invalid_Escape, esc_offset)
			return false
		}
		s.pos += 1
	}
	return true
}

@(private)
is_alpha :: proc(c: byte) -> bool {
	switch c {
	case 'a' ..= 'z', 'A' ..= 'Z':
		return true
	}
	return false
}

@(private)
is_alnum :: proc(c: byte) -> bool {
	switch c {
	case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
		return true
	}
	return false
}

@(private)
is_hex_digit :: proc(c: byte) -> bool {
	switch c {
	case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
		return true
	}
	return false
}

// Blank node label characters are checked loosely for non-ASCII: any byte
// of a multi-byte UTF-8 sequence is accepted rather than validating the
// exact PN_CHARS ranges. Tightened if the W3C suite (RDF-T-0010) demands.
@(private)
is_label_start :: proc(c: byte) -> bool {
	return is_alnum(c) || c == '_' || c >= 0x80
}

@(private)
is_label_char :: proc(c: byte) -> bool {
	return is_alnum(c) || c == '_' || c == '-' || c >= 0x80
}
