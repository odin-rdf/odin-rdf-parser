package scanner

import "core:mem"
import "core:testing"

@(test)
test_full_statement :: proc(t: ^testing.T) {
	src := `<http://example.org/s> <http://example.org/p> "chat"@fr--ltr . # trailing comment`
	s: Scanner
	scanner_init(&s, transmute([]byte)src)

	expected := [?]Token_Kind{.IRI_Ref, .IRI_Ref, .String_Literal, .Lang_Tag, .Dot}
	for want, i in expected {
		tok, ok := scanner_next(&s)
		testing.expectf(t, ok, "token %d missing", i)
		testing.expect_value(t, tok.kind, want)
	}
	_, ok := scanner_next(&s)
	testing.expect(t, !ok)
	testing.expect_value(t, s.err.kind, Error_Kind.None)
}

@(test)
test_token_texts_strip_delimiters :: proc(t: ^testing.T) {
	src := `<http://example.org/s> _:b0 "hello" @fr-CA--rtl ^^ <<( )>>`
	s: Scanner
	scanner_init(&s, transmute([]byte)src)

	iri, _ := scanner_next(&s)
	testing.expect_value(t, iri.text, "http://example.org/s")
	bnode, _ := scanner_next(&s)
	testing.expect_value(t, bnode.text, "b0")
	str, _ := scanner_next(&s)
	testing.expect_value(t, str.text, "hello")
	lang, _ := scanner_next(&s)
	testing.expect_value(t, lang.text, "fr-CA--rtl")
	marker, _ := scanner_next(&s)
	testing.expect_value(t, marker.kind, Token_Kind.Datatype_Marker)
	open, _ := scanner_next(&s)
	testing.expect_value(t, open.kind, Token_Kind.Triple_Term_Open)
	close_tok, _ := scanner_next(&s)
	testing.expect_value(t, close_tok.kind, Token_Kind.Triple_Term_Close)
}

@(test)
test_escape_flag :: proc(t: ^testing.T) {
	src := `"plain" "esc\n" <http://a/b> <http://a/\u0041>`
	s: Scanner
	scanner_init(&s, transmute([]byte)src)

	plain, _ := scanner_next(&s)
	testing.expect(t, !plain.has_escape)
	escaped, _ := scanner_next(&s)
	testing.expect(t, escaped.has_escape)
	testing.expect_value(t, escaped.text, `esc\n`)
	iri_plain, _ := scanner_next(&s)
	testing.expect(t, !iri_plain.has_escape)
	iri_escaped, _ := scanner_next(&s)
	testing.expect(t, iri_escaped.has_escape)
}

@(test)
test_blank_node_label_dot_boundary :: proc(t: ^testing.T) {
	// A trailing dot terminates the statement; an internal dot is label.
	src := `_:b1. _:a.c .`
	s: Scanner
	scanner_init(&s, transmute([]byte)src)

	first, _ := scanner_next(&s)
	testing.expect_value(t, first.text, "b1")
	dot, _ := scanner_next(&s)
	testing.expect_value(t, dot.kind, Token_Kind.Dot)
	second, _ := scanner_next(&s)
	testing.expect_value(t, second.text, "a.c")
	dot2, _ := scanner_next(&s)
	testing.expect_value(t, dot2.kind, Token_Kind.Dot)
}

@(test)
test_positions :: proc(t: ^testing.T) {
	src := "# comment line\n<http://a> <http://b>\n  \"x\" ."
	s: Scanner
	scanner_init(&s, transmute([]byte)src)

	first, _ := scanner_next(&s)
	testing.expect_value(t, first.line, 2)
	testing.expect_value(t, first.column, 1)
	second, _ := scanner_next(&s)
	testing.expect_value(t, second.line, 2)
	testing.expect_value(t, second.column, 12)
	third, _ := scanner_next(&s)
	testing.expect_value(t, third.line, 3)
	testing.expect_value(t, third.column, 3)
}

@(test)
test_scanner_errors :: proc(t: ^testing.T) {
	cases := [?]struct {
		src:  string,
		kind: Error_Kind,
	} {
		{`<http://unterminated`, .Unterminated_IRI},
		{`<http://a b>`, .Invalid_IRI_Character},
		{`"unterminated`, .Unterminated_String},
		{"\"raw\nnewline\"", .Invalid_String_Character},
		{`"bad esc \x"`, .Invalid_Escape},
		{`<http://a/\n>`, .Invalid_Escape},
		{`"short hex \u12"`, .Invalid_Escape},
		{`_x`, .Invalid_Blank_Node_Label},
		{`_:`, .Invalid_Blank_Node_Label},
		{`@1fr`, .Invalid_Lang_Tag},
		{`@fr--`, .Invalid_Lang_Tag},
		{`^x`, .Unexpected_Character},
		{`)>`, .Unexpected_Character},
		{`%`, .Unexpected_Character},
	}
	for c in cases {
		s: Scanner
		scanner_init(&s, transmute([]byte)c.src)
		for {
			_, ok := scanner_next(&s)
			if !ok {
				break
			}
		}
		testing.expectf(t, s.err.kind == c.kind, "%q: got %v, want %v", c.src, s.err.kind, c.kind)
	}
}

@(test)
test_error_position :: proc(t: ^testing.T) {
	src := "<http://a> <http://b>\n\"x\" %"
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	for {
		_, ok := scanner_next(&s)
		if !ok {
			break
		}
	}
	testing.expect_value(t, s.err.kind, Error_Kind.Unexpected_Character)
	testing.expect_value(t, s.err.line, 2)
	testing.expect_value(t, s.err.column, 5)
}

@(test)
test_scanning_never_allocates :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	src := `<http://example.org/s> <http://example.org/p> "escA"@en--ltr <<( )>> _:b.x . # c`
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	for {
		_, ok := scanner_next(&s)
		if !ok {
			break
		}
	}
	testing.expect_value(t, len(track.allocation_map), 0)
}
