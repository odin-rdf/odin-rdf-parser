// Package ttl is the shared tokenizer for the Turtle-family RDF formats
// (Turtle, TriG). It is internal to odin-rdf-parser — not part of the
// public API, no compatibility promises.
//
// Tokens borrow from the caller-owned source buffer (ADR RDF-A-0001);
// scanning never allocates. The package shares the Error type and the
// character-class primitives with the line-based scanner
// (rdf/internal/scanner) as functions, but no scanner state machine —
// the lexical grounds differ too much (RDF-I-0003 design decision).
package ttl

import "core:unicode/utf8"

import scan "../scanner"

// Error and Error_Kind are shared with the line-based scanner so every
// format package reports through one error type.
Error :: scan.Error
Error_Kind :: scan.Error_Kind

Scanner :: struct {
	source:     []byte,
	pos:        int,
	line:       int, // 1-based
	line_start: int, // byte offset where the current line begins
	err:        scan.Error,
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

	switch c := s.source[s.pos]; c {
	case '<':
		// '<<(' and '<<' are unambiguous: no legal Turtle construct puts
		// a '(' directly after a reified-triple open, and IRIREF forbids
		// '<' in content.
		if peek(s, 1) == '<' {
			if peek(s, 2) == '(' {
				s.pos += 3
				tok.kind = .Triple_Term_Open
				return tok, true
			}
			s.pos += 2
			tok.kind = .Reified_Open
			return tok, true
		}
		return scan_iri_ref(s, &tok)

	case '>':
		if peek(s, 1) == '>' {
			s.pos += 2
			tok.kind = .Reified_Close
			return tok, true
		}
		set_error(s, .Unexpected_Character, start)
		return {}, false

	case '"', '\'':
		return scan_string(s, &tok, c)

	case '_':
		return scan_blank_node(s, &tok)

	case '@':
		return scan_at(s, &tok)

	case '^':
		if peek(s, 1) == '^' {
			s.pos += 2
			tok.kind = .Datatype_Marker
			return tok, true
		}
		set_error(s, .Unexpected_Character, start)
		return {}, false

	case ';':
		s.pos += 1
		tok.kind = .Semicolon
		return tok, true
	case ',':
		s.pos += 1
		tok.kind = .Comma
		return tok, true
	case '[':
		s.pos += 1
		tok.kind = .L_Bracket
		return tok, true
	case ']':
		s.pos += 1
		tok.kind = .R_Bracket
		return tok, true
	case '(':
		s.pos += 1
		tok.kind = .L_Paren
		return tok, true

	case ')':
		// ')>>' is unambiguous for the same reason as '<<(': a collection
		// can never be the last constituent before a reified-triple close.
		if peek(s, 1) == '>' && peek(s, 2) == '>' {
			s.pos += 3
			tok.kind = .Triple_Term_Close
			return tok, true
		}
		s.pos += 1
		tok.kind = .R_Paren
		return tok, true

	case '{':
		if peek(s, 1) == '|' {
			s.pos += 2
			tok.kind = .Annotation_Open
			return tok, true
		}
		s.pos += 1
		tok.kind = .L_Brace
		return tok, true

	case '|':
		if peek(s, 1) == '}' {
			s.pos += 2
			tok.kind = .Annotation_Close
			return tok, true
		}
		set_error(s, .Unexpected_Character, start)
		return {}, false

	case '}':
		s.pos += 1
		tok.kind = .R_Brace
		return tok, true

	case '~':
		s.pos += 1
		tok.kind = .Tilde
		return tok, true

	case '.':
		// A dot is a number only when digits follow (".5"); otherwise it
		// is the statement terminator.
		if is_digit(peek(s, 1)) {
			return scan_number(s, &tok)
		}
		s.pos += 1
		tok.kind = .Dot
		return tok, true

	case '+', '-', '0' ..= '9':
		return scan_number(s, &tok)

	case ':':
		return scan_pname(s, &tok, start)

	case:
		// PN_CHARS_BASE start: a bare keyword or the prefix part of a
		// prefixed name.
		return scan_name(s, &tok)
	}
}

@(private)
peek :: proc(s: ^Scanner, ahead: int) -> byte {
	if s.pos + ahead < len(s.source) {
		return s.source[s.pos + ahead]
	}
	return 0
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

@(private)
scan_iri_ref :: proc(s: ^Scanner, tok: ^Token) -> (Token, bool) {
	start := s.pos
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
			return tok^, true
		case c == '\\':
			tok.has_escape = true
			esc := s.pos
			value, uok := scan_uchar(s)
			if !uok {
				return {}, false
			}
			// An escape may not smuggle in a character IRIREF forbids.
			forbidden := value <= 0x20
			switch value {
			case '<', '>', '"', '{', '}', '|', '^', '`', '\\':
				forbidden = true
			}
			if forbidden {
				set_error(s, .Invalid_IRI_Character, esc)
				return {}, false
			}
		case c <= 0x20 || c == '<' || c == '"' || c == '{' || c == '}' || c == '|' || c == '^' || c == '`':
			set_error(s, .Invalid_IRI_Character, s.pos)
			return {}, false
		case:
			s.pos += 1
		}
	}
}

// scan_uchar validates a UCHAR escape (\uXXXX or \UXXXXXXXX), the only
// escapes IRIREF permits, and returns the decoded codepoint. s.pos is
// at the backslash on entry.
@(private)
scan_uchar :: proc(s: ^Scanner) -> (value: u32, ok: bool) {
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
	return 0, false
}

// scan_echar_or_uchar validates an ECHAR or UCHAR escape inside a string
// literal. s.pos is at the backslash on entry.
@(private)
scan_echar_or_uchar :: proc(s: ^Scanner) -> bool {
	esc := s.pos
	s.pos += 1
	if s.pos < len(s.source) {
		switch s.source[s.pos] {
		case 't', 'b', 'n', 'r', 'f', '"', '\'', '\\':
			s.pos += 1
			return true
		case 'u':
			s.pos += 1
			_, ok := scan_hex(s, 4, esc)
			return ok
		case 'U':
			s.pos += 1
			_, ok := scan_hex(s, 8, esc)
			return ok
		}
	}
	set_error(s, .Invalid_Escape, esc)
	return false
}

// scan_hex consumes n hex digits and validates the decoded codepoint:
// surrogates and values beyond U+10FFFF are not characters and are
// rejected wherever UCHAR appears (W3C bad-numeric-escape tests).
@(private)
scan_hex :: proc(s: ^Scanner, n: int, esc_offset: int) -> (value: u32, ok: bool) {
	for _ in 0 ..< n {
		if s.pos >= len(s.source) || !scan.is_hex_digit(s.source[s.pos]) {
			set_error(s, .Invalid_Escape, esc_offset)
			return 0, false
		}
		c := s.source[s.pos]
		value <<= 4
		switch {
		case c <= '9':
			value |= u32(c - '0')
		case c >= 'a':
			value |= u32(c - 'a' + 10)
		case:
			value |= u32(c - 'A' + 10)
		}
		s.pos += 1
	}
	if (value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF {
		set_error(s, .Invalid_Escape, esc_offset)
		return 0, false
	}
	return value, true
}

@(private)
scan_string :: proc(s: ^Scanner, tok: ^Token, quote: byte) -> (Token, bool) {
	if peek(s, 1) == quote && peek(s, 2) == quote {
		return scan_long_string(s, tok, quote)
	}
	start := s.pos
	s.pos += 1
	content_start := s.pos
	for {
		if s.pos >= len(s.source) {
			set_error(s, .Unterminated_String, start)
			return {}, false
		}
		c := s.source[s.pos]
		switch {
		case c == quote:
			tok.kind = .String_Literal
			tok.text = string(s.source[content_start:s.pos])
			s.pos += 1
			return tok^, true
		case c == '\\':
			tok.has_escape = true
			if !scan_echar_or_uchar(s) {
				return {}, false
			}
		case c == '\n' || c == '\r':
			set_error(s, .Invalid_String_Character, s.pos)
			return {}, false
		case:
			s.pos += 1
		}
	}
}

@(private)
scan_long_string :: proc(s: ^Scanner, tok: ^Token, quote: byte) -> (Token, bool) {
	start := s.pos
	s.pos += 3
	content_start := s.pos
	for {
		if s.pos >= len(s.source) {
			set_error(s, .Unterminated_Long_String, start)
			return {}, false
		}
		c := s.source[s.pos]
		switch {
		case c == quote:
			// The literal closes at the FIRST run of three quotes; any
			// further quotes belong to following tokens (grammar: content
			// quote runs are at most two and must be followed by more
			// content). '"""abc""""' is therefore a syntax error, not a
			// literal ending in '"'.
			run_start := s.pos
			for s.pos < len(s.source) && s.source[s.pos] == quote && s.pos - run_start < 3 {
				s.pos += 1
			}
			if s.pos - run_start == 3 {
				tok.kind = .String_Literal
				tok.long_string = true
				tok.text = string(s.source[content_start:run_start])
				return tok^, true
			}
		case c == '\\':
			tok.has_escape = true
			if !scan_echar_or_uchar(s) {
				return {}, false
			}
		case c == '\n':
			s.pos += 1
			s.line += 1
			s.line_start = s.pos
		case:
			s.pos += 1
		}
	}
}

@(private)
scan_blank_node :: proc(s: ^Scanner, tok: ^Token) -> (Token, bool) {
	start := s.pos
	if peek(s, 1) != ':' {
		set_error(s, .Invalid_Blank_Node_Label, start)
		return {}, false
	}
	s.pos += 2
	content_start := s.pos
	r, n := decode_rune_at(s, s.pos)
	if n == 0 || !(is_pn_chars_u(r) || is_digit_rune(r)) {
		set_error(s, .Invalid_Blank_Node_Label, start)
		return {}, false
	}
	s.pos += n
	for s.pos < len(s.source) {
		if s.source[s.pos] == '.' {
			// A dot run is label content only when a label character
			// follows it; a trailing dot terminates the statement.
			j := s.pos
			for j < len(s.source) && s.source[j] == '.' {
				j += 1
			}
			r2, n2 := decode_rune_at(s, j)
			if n2 == 0 || !is_pn_chars(r2) {
				break
			}
			s.pos = j
			continue
		}
		r, n = decode_rune_at(s, s.pos)
		if n == 0 || !is_pn_chars(r) {
			break
		}
		s.pos += n
	}
	tok.kind = .Blank_Node_Label
	tok.text = string(s.source[content_start:s.pos])
	return tok^, true
}

// scan_at handles '@prefix', '@base', and LANGTAG. The directives are
// reserved only in their exact bare form: '@prefix-x' is a language tag
// by maximal munch.
@(private)
scan_at :: proc(s: ^Scanner, tok: ^Token) -> (Token, bool) {
	start := s.pos
	s.pos += 1
	content_start := s.pos
	for s.pos < len(s.source) && scan.is_alpha(s.source[s.pos]) {
		s.pos += 1
	}
	word := string(s.source[content_start:s.pos])
	if s.pos >= len(s.source) || s.source[s.pos] != '-' {
		switch word {
		case "prefix":
			tok.kind = .At_Prefix
			return tok^, true
		case "base":
			tok.kind = .At_Base
			return tok^, true
		case "version":
			tok.kind = .At_Version
			return tok^, true
		}
	}
	// BCP47 well-formedness (RDF 1.2): subtags are 1-8 characters, the
	// primary subtag alphabetic — same enforcement as the line scanner.
	if n := len(word); n == 0 || n > 8 {
		set_error(s, .Invalid_Lang_Tag, start)
		return {}, false
	}
	subtags: for s.pos < len(s.source) && s.source[s.pos] == '-' {
		if s.pos + 1 < len(s.source) && s.source[s.pos + 1] == '-' {
			// RDF 1.2 base direction suffix: '--' [a-zA-Z]+
			s.pos += 2
			dir_start := s.pos
			for s.pos < len(s.source) && scan.is_alpha(s.source[s.pos]) {
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
		for s.pos < len(s.source) && scan.is_alnum(s.source[s.pos]) {
			s.pos += 1
		}
		if n := s.pos - seg_start; n == 0 || n > 8 {
			set_error(s, .Invalid_Lang_Tag, start)
			return {}, false
		}
	}
	tok.kind = .Lang_Tag
	tok.text = string(s.source[content_start:s.pos])
	return tok^, true
}

@(private)
scan_number :: proc(s: ^Scanner, tok: ^Token) -> (Token, bool) {
	start := s.pos
	if s.source[s.pos] == '+' || s.source[s.pos] == '-' {
		s.pos += 1
	}
	int_digits := scan_digits(s)
	frac_digits := 0
	kind := Token_Kind.Integer
	if s.pos < len(s.source) && s.source[s.pos] == '.' {
		// The dot joins the number only for "1.5" (DECIMAL) or "1.e0"
		// (DOUBLE with empty fraction); a bare trailing dot terminates
		// the statement instead.
		if is_digit(peek(s, 1)) {
			s.pos += 1
			frac_digits = scan_digits(s)
			kind = .Decimal
		} else if int_digits > 0 && starts_exponent(s, 1) {
			s.pos += 1
			kind = .Decimal // upgraded to Double below
		}
	}
	if starts_exponent(s, 0) {
		s.pos += 1 // 'e' | 'E'
		if s.source[s.pos] == '+' || s.source[s.pos] == '-' {
			s.pos += 1
		}
		_ = scan_digits(s)
		kind = .Double
	}
	if int_digits == 0 && frac_digits == 0 {
		set_error(s, .Invalid_Number, start)
		return {}, false
	}
	tok.kind = kind
	tok.text = string(s.source[start:s.pos])
	return tok^, true
}

// starts_exponent reports whether a complete EXPONENT ([eE] [+-]? [0-9]+)
// begins `ahead` bytes past the current position.
@(private)
starts_exponent :: proc(s: ^Scanner, ahead: int) -> bool {
	i := s.pos + ahead
	if i >= len(s.source) || (s.source[i] != 'e' && s.source[i] != 'E') {
		return false
	}
	i += 1
	if i < len(s.source) && (s.source[i] == '+' || s.source[i] == '-') {
		i += 1
	}
	return i < len(s.source) && is_digit(s.source[i])
}

@(private)
scan_digits :: proc(s: ^Scanner) -> (count: int) {
	for s.pos < len(s.source) && is_digit(s.source[s.pos]) {
		s.pos += 1
		count += 1
	}
	return
}

// scan_name scans a bare name starting with PN_CHARS_BASE: either one of
// the keywords (a, true, false, PREFIX, BASE, GRAPH) or the prefix part
// of a prefixed name.
@(private)
scan_name :: proc(s: ^Scanner, tok: ^Token) -> (Token, bool) {
	start := s.pos
	r, n := decode_rune_at(s, s.pos)
	if n == 0 || !is_pn_chars_base(r) {
		set_error(s, .Unexpected_Character, start)
		return {}, false
	}
	s.pos += n
	scan_prefix_body(s)
	if s.pos < len(s.source) && s.source[s.pos] == ':' {
		return scan_pname(s, tok, start)
	}
	word := string(s.source[start:s.pos])
	switch {
	case word == "a":
		tok.kind = .A
		return tok^, true
	case word == "true" || word == "false":
		tok.kind = .Boolean
		tok.text = word
		return tok^, true
	case eq_fold_ascii(word, "prefix"):
		tok.kind = .Sparql_Prefix
		return tok^, true
	case eq_fold_ascii(word, "base"):
		tok.kind = .Sparql_Base
		return tok^, true
	case eq_fold_ascii(word, "version"):
		tok.kind = .Sparql_Version
		return tok^, true
	case eq_fold_ascii(word, "graph"):
		tok.kind = .Graph_Keyword
		return tok^, true
	}
	set_error(s, .Unknown_Keyword, start)
	return {}, false
}

// scan_prefix_body consumes the rest of a PN_PREFIX after its first
// character: (PN_CHARS | '.')* PN_CHARS — dots interior only.
@(private)
scan_prefix_body :: proc(s: ^Scanner) {
	for s.pos < len(s.source) {
		if s.source[s.pos] == '.' {
			j := s.pos
			for j < len(s.source) && s.source[j] == '.' {
				j += 1
			}
			r, n := decode_rune_at(s, j)
			if n == 0 || !is_pn_chars(r) {
				return
			}
			s.pos = j
			continue
		}
		r, n := decode_rune_at(s, s.pos)
		if n == 0 || !is_pn_chars(r) {
			return
		}
		s.pos += n
	}
}

// scan_pname scans a prefixed name from its ':' separator; start is the
// offset of the prefix (equal to s.pos for the empty default prefix).
@(private)
scan_pname :: proc(s: ^Scanner, tok: ^Token, start: int) -> (Token, bool) {
	s.pos += 1 // ':'
	if !scan_local(s, tok) {
		return {}, false
	}
	tok.kind = .PName
	tok.text = string(s.source[start:s.pos])
	return tok^, true
}

// scan_local consumes an optional PN_LOCAL. An empty local part is valid
// (PNAME_NS used as a term or in a directive).
@(private)
scan_local :: proc(s: ^Scanner, tok: ^Token) -> bool {
	if !local_char_at(s, s.pos, true) {
		return true
	}
	if !consume_local_char(s, tok) {
		return false
	}
	for {
		if s.pos < len(s.source) && s.source[s.pos] == '.' {
			// A dot run is local content only when more local follows.
			j := s.pos
			for j < len(s.source) && s.source[j] == '.' {
				j += 1
			}
			if !local_char_at(s, j, false) {
				break
			}
			s.pos = j
			if !consume_local_char(s, tok) {
				return false
			}
			continue
		}
		if !local_char_at(s, s.pos, false) {
			break
		}
		if !consume_local_char(s, tok) {
			return false
		}
	}
	return true
}

// local_char_at reports whether a PN_LOCAL character (or PLX escape)
// starts at the given offset. The first character excludes '-', the
// middle dot, and combining marks (PN_CHARS_U | ':' | [0-9] | PLX).
@(private)
local_char_at :: proc(s: ^Scanner, at: int, first: bool) -> bool {
	if at >= len(s.source) {
		return false
	}
	c := s.source[at]
	if c == ':' || c == '%' || c == '\\' {
		return true
	}
	r, n := decode_rune_at_offset(s, at)
	if n == 0 {
		return false
	}
	if first {
		return is_pn_chars_u(r) || is_digit_rune(r)
	}
	return is_pn_chars(r)
}

// consume_local_char consumes one PN_LOCAL constituent whose class was
// already validated by local_char_at.
@(private)
consume_local_char :: proc(s: ^Scanner, tok: ^Token) -> bool {
	switch s.source[s.pos] {
	case '%':
		// PERCENT is content: validated, never decoded.
		if s.pos + 2 >= len(s.source) ||
		   !scan.is_hex_digit(s.source[s.pos + 1]) ||
		   !scan.is_hex_digit(s.source[s.pos + 2]) {
			set_error(s, .Invalid_Percent_Encoding, s.pos)
			return false
		}
		s.pos += 3
	case '\\':
		if s.pos + 1 >= len(s.source) || !is_pn_local_esc(s.source[s.pos + 1]) {
			set_error(s, .Invalid_Escape, s.pos)
			return false
		}
		tok.has_escape = true
		s.pos += 2
	case:
		_, n := decode_rune_at(s, s.pos)
		s.pos += n
	}
	return true
}

@(private)
is_pn_local_esc :: proc(c: byte) -> bool {
	switch c {
	case '_', '~', '.', '-', '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=', '/', '?', '#', '@', '%':
		return true
	}
	return false
}

@(private)
decode_rune_at :: proc(s: ^Scanner, at: int) -> (r: rune, n: int) {
	return decode_rune_at_offset(s, at)
}

@(private)
decode_rune_at_offset :: proc(s: ^Scanner, at: int) -> (r: rune, n: int) {
	if at >= len(s.source) {
		return 0, 0
	}
	c := s.source[at]
	if c < 0x80 {
		return rune(c), 1
	}
	r, n = utf8.decode_rune(s.source[at:])
	// A genuine U+FFFD decodes as RUNE_ERROR with size 3 and is a legal
	// PN_CHARS_BASE character (the W3C boundary tests use it); only a
	// size-1 error marks invalid bytes.
	if r == utf8.RUNE_ERROR && n <= 1 {
		return 0, 0
	}
	return r, n
}

@(private)
is_digit :: proc(c: byte) -> bool {
	return c >= '0' && c <= '9'
}

@(private)
is_digit_rune :: proc(r: rune) -> bool {
	return r >= '0' && r <= '9'
}

// is_pn_chars_base implements the PN_CHARS_BASE production of the Turtle
// grammar exactly — unlike the line-based scanner's loose byte check,
// prefixed names get full rune validation (the Turtle suites test it).
@(private)
is_pn_chars_base :: proc(r: rune) -> bool {
	switch r {
	case 'A' ..= 'Z', 'a' ..= 'z',
	     0x00C0 ..= 0x00D6, 0x00D8 ..= 0x00F6, 0x00F8 ..= 0x02FF,
	     0x0370 ..= 0x037D, 0x037F ..= 0x1FFF, 0x200C ..= 0x200D,
	     0x2070 ..= 0x218F, 0x2C00 ..= 0x2FEF, 0x3001 ..= 0xD7FF,
	     0xF900 ..= 0xFDCF, 0xFDF0 ..= 0xFFFD, 0x10000 ..= 0xEFFFF:
		return true
	}
	return false
}

@(private)
is_pn_chars_u :: proc(r: rune) -> bool {
	return r == '_' || is_pn_chars_base(r)
}

@(private)
is_pn_chars :: proc(r: rune) -> bool {
	switch r {
	case '-', '0' ..= '9', 0x00B7, 0x0300 ..= 0x036F, 0x203F ..= 0x2040:
		return true
	}
	return is_pn_chars_u(r)
}

// eq_fold_ascii compares a scanned word against a lowercase keyword,
// ASCII case-insensitively.
@(private)
eq_fold_ascii :: proc(word, keyword: string) -> bool {
	if len(word) != len(keyword) {
		return false
	}
	for i in 0 ..< len(word) {
		c := word[i]
		if 'A' <= c && c <= 'Z' {
			c += 32
		}
		if c != keyword[i] {
			return false
		}
	}
	return true
}
