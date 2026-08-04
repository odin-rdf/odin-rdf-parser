package ttl

import "core:mem"
import "core:testing"

scan_kinds :: proc(t: ^testing.T, src: string, expected: []Token_Kind, loc := #caller_location) {
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	for want, i in expected {
		tok, ok := scanner_next(&s)
		testing.expectf(t, ok, "%q: token %d missing (err %v)", src, i, s.err.kind, loc = loc)
		testing.expectf(t, tok.kind == want, "%q: token %d: got %v, want %v", src, i, tok.kind, want, loc = loc)
	}
	_, ok := scanner_next(&s)
	testing.expectf(t, !ok, "%q: extra token after expected %d", src, len(expected), loc = loc)
	testing.expectf(t, s.err.kind == Error_Kind.None, "%q: err %v", src, s.err.kind, loc = loc)
}

@(test)
test_directives_and_simple_statement :: proc(t: ^testing.T) {
	scan_kinds(
		t,
		"@prefix foaf: <http://xmlns.com/foaf/0.1/> .\n" +
		"@base <http://example.org/> .\n" +
		"PREFIX ex: <http://example.org/ns#>\n" +
		"BaSe <http://example.org/>\n" +
		"foaf:alice a foaf:Person ; foaf:knows _:bob , [ ] .",
		{
			.At_Prefix, .PName, .IRI_Ref, .Dot,
			.At_Base, .IRI_Ref, .Dot,
			.Sparql_Prefix, .PName, .IRI_Ref,
			.Sparql_Base, .IRI_Ref,
			.PName, .A, .PName, .Semicolon, .PName, .Blank_Node_Label, .Comma, .L_Bracket, .R_Bracket, .Dot,
		},
	)
}

@(test)
test_rdf12_punctuation :: proc(t: ^testing.T) {
	scan_kinds(
		t,
		"<< :s :p :o >> ~ _:r {| :q :v |} <<( :s :p :o )>> { }",
		{
			.Reified_Open, .PName, .PName, .PName, .Reified_Close, .Tilde, .Blank_Node_Label,
			.Annotation_Open, .PName, .PName, .Annotation_Close,
			.Triple_Term_Open, .PName, .PName, .PName, .Triple_Term_Close,
			.L_Brace, .R_Brace,
		},
	)
}

@(test)
test_collections_and_numbers :: proc(t: ^testing.T) {
	scan_kinds(
		t,
		"( 5 -5 +5 4.2 .5 1e5 1.e0 1.5E-3 ) true false",
		{
			.L_Paren, .Integer, .Integer, .Integer, .Decimal, .Decimal,
			.Double, .Double, .Double, .R_Paren, .Boolean, .Boolean,
		},
	)
}

@(test)
test_number_dot_boundary :: proc(t: ^testing.T) {
	// "1." is INTEGER followed by the statement terminator.
	src := ":s :p 1. "
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	_, _ = scanner_next(&s)
	_, _ = scanner_next(&s)
	num, _ := scanner_next(&s)
	testing.expect_value(t, num.kind, Token_Kind.Integer)
	testing.expect_value(t, num.text, "1")
	dot, _ := scanner_next(&s)
	testing.expect_value(t, dot.kind, Token_Kind.Dot)
}

@(test)
test_number_texts :: proc(t: ^testing.T) {
	src := "-4.2 +.5 1.e0"
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	a, _ := scanner_next(&s)
	testing.expect_value(t, a.text, "-4.2")
	testing.expect_value(t, a.kind, Token_Kind.Decimal)
	b, _ := scanner_next(&s)
	testing.expect_value(t, b.text, "+.5")
	testing.expect_value(t, b.kind, Token_Kind.Decimal)
	c, _ := scanner_next(&s)
	testing.expect_value(t, c.text, "1.e0")
	testing.expect_value(t, c.kind, Token_Kind.Double)
}

@(test)
test_pname_texts :: proc(t: ^testing.T) {
	// PName text keeps the colon; split at the FIRST colon. Locals may
	// contain colons, interior dots, percent encodings, and escapes.
	cases := [?]struct {
		src:        string,
		text:       string,
		has_escape: bool,
	} {
		{"foaf:name", "foaf:name", false},
		{":x", ":x", false},
		{":", ":", false},
		{"p:", "p:", false},
		{"ex:a.b", "ex:a.b", false},
		{"ex:a:b", "ex:a:b", false},
		{"ex:%41x", "ex:%41x", false},
		{`ex:\~x`, `ex:\~x`, true},
		{"ex:0", "ex:0", false},
		{"a.b:x", "a.b:x", false},
	}
	for c in cases {
		s: Scanner
		scanner_init(&s, transmute([]byte)c.src)
		tok, ok := scanner_next(&s)
		testing.expectf(t, ok, "%q: no token (err %v)", c.src, s.err.kind)
		testing.expectf(t, tok.kind == .PName, "%q: got %v", c.src, tok.kind)
		testing.expectf(t, tok.text == c.text, "%q: text %q, want %q", c.src, tok.text, c.text)
		testing.expectf(t, tok.has_escape == c.has_escape, "%q: has_escape %v", c.src, tok.has_escape)
	}
}

@(test)
test_pname_trailing_dot_boundary :: proc(t: ^testing.T) {
	src := "ex:name. :s"
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	pn, _ := scanner_next(&s)
	testing.expect_value(t, pn.text, "ex:name")
	dot, _ := scanner_next(&s)
	testing.expect_value(t, dot.kind, Token_Kind.Dot)
	pn2, _ := scanner_next(&s)
	testing.expect_value(t, pn2.text, ":s")
}

@(test)
test_unicode_pnames :: proc(t: ^testing.T) {
	src := "ért:szó _:łabel"
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	pn, ok := scanner_next(&s)
	testing.expect(t, ok)
	testing.expect_value(t, pn.kind, Token_Kind.PName)
	testing.expect_value(t, pn.text, "ért:szó")
	bn, ok2 := scanner_next(&s)
	testing.expect(t, ok2)
	testing.expect_value(t, bn.text, "łabel")
}

@(test)
test_string_forms :: proc(t: ^testing.T) {
	src := `"double" 'single' """long "quoted" content""" '''it's long'''`
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	a, _ := scanner_next(&s)
	testing.expect_value(t, a.text, "double")
	b, _ := scanner_next(&s)
	testing.expect_value(t, b.text, "single")
	c, _ := scanner_next(&s)
	testing.expect_value(t, c.text, `long "quoted" content`)
	d, _ := scanner_next(&s)
	testing.expect_value(t, d.text, "it's long")
}

@(test)
test_long_string_quote_runs :: proc(t: ^testing.T) {
	// The literal closes at the FIRST run of three quotes; interior runs
	// of one or two are content.
	src := `"""a"" b"""  ""  """"""`
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	a, _ := scanner_next(&s)
	testing.expect_value(t, a.text, `a"" b`)
	b, _ := scanner_next(&s)
	testing.expect_value(t, b.text, "")
	testing.expect(t, !b.long_string)
	c, _ := scanner_next(&s)
	testing.expect_value(t, c.text, "")
	testing.expect(t, c.long_string)

	// A run of four quotes is a closed literal plus a stray quote —
	// a syntax error, matching the W3C bad-string tests.
	bad := `"""abc""""@en`
	scanner_init(&s, transmute([]byte)bad)
	first, ok := scanner_next(&s)
	testing.expect(t, ok)
	testing.expect_value(t, first.text, "abc")
	for {
		_, more := scanner_next(&s)
		if !more {
			break
		}
	}
	testing.expect_value(t, s.err.kind, Error_Kind.Unterminated_String)
}

@(test)
test_long_string_line_tracking :: proc(t: ^testing.T) {
	src := "\"\"\"line1\nline2\nline3\"\"\" :after"
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	str, _ := scanner_next(&s)
	testing.expect_value(t, str.line, 1)
	testing.expect_value(t, str.text, "line1\nline2\nline3")
	after, _ := scanner_next(&s)
	testing.expect_value(t, after.line, 3)
	testing.expect_value(t, after.column, 10)
}

@(test)
test_lang_tags_and_directive_ambiguity :: proc(t: ^testing.T) {
	// '@prefix-x' is a language tag by maximal munch; bare '@prefix' is
	// the directive.
	src := `"a"@en "b"@fr-CA--rtl "c"@prefix-x`
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	_, _ = scanner_next(&s)
	en, _ := scanner_next(&s)
	testing.expect_value(t, en.kind, Token_Kind.Lang_Tag)
	testing.expect_value(t, en.text, "en")
	_, _ = scanner_next(&s)
	fr, _ := scanner_next(&s)
	testing.expect_value(t, fr.text, "fr-CA--rtl")
	_, _ = scanner_next(&s)
	px, _ := scanner_next(&s)
	testing.expect_value(t, px.kind, Token_Kind.Lang_Tag)
	testing.expect_value(t, px.text, "prefix-x")
}

@(test)
test_keywords :: proc(t: ^testing.T) {
	scan_kinds(t, "a true false prefix PREFIX base BASE graph GRAPH Graph", {
		.A, .Boolean, .Boolean,
		.Sparql_Prefix, .Sparql_Prefix, .Sparql_Base, .Sparql_Base,
		.Graph_Keyword, .Graph_Keyword, .Graph_Keyword,
	})
}

@(test)
test_empty_and_datatyped :: proc(t: ^testing.T) {
	scan_kinds(t, `<> <#f> "x"^^ex:dt`, {.IRI_Ref, .IRI_Ref, .String_Literal, .Datatype_Marker, .PName})
}

@(test)
test_scanner_errors :: proc(t: ^testing.T) {
	cases := [?]struct {
		src:  string,
		kind: Error_Kind,
	} {
		{`"""unterminated`, .Unterminated_Long_String},
		{"'''also", .Unterminated_Long_String},
		{`"unterminated`, .Unterminated_String},
		{"\"raw\nnewline\"", .Invalid_String_Character},
		{`"bad esc \x"`, .Invalid_Escape},
		{`<http://a/\n>`, .Invalid_Escape},
		{`<http://a b>`, .Invalid_IRI_Character},
		{`<http://unterminated`, .Unterminated_IRI},
		{`ex:\y`, .Invalid_Escape},
		{`ex:%GG`, .Invalid_Percent_Encoding},
		{`ex:%4`, .Invalid_Percent_Encoding},
		{`abc def`, .Unknown_Keyword},
		{`+`, .Invalid_Number},
		{`+.`, .Invalid_Number},
		{`>`, .Unexpected_Character},
		{`|`, .Unexpected_Character},
		{`^x`, .Unexpected_Character},
		{`_x`, .Invalid_Blank_Node_Label},
		{`_:-x`, .Invalid_Blank_Node_Label},
		{`@1fr`, .Invalid_Lang_Tag},
		{`"x"@fr--`, .Invalid_Lang_Tag},
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
	src := ":s :p\n  ^x ."
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
	testing.expect_value(t, s.err.column, 3)
}

@(test)
test_scanning_never_allocates :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	src := "@prefix ex: <http://e/> . ex:s a ex:T ; ex:p ( 1 4.2 1e5 \"x\"@en--ltr '''long\n''' ) , [ ex:q <<( :s :p :o )>> ] ."
	s: Scanner
	scanner_init(&s, transmute([]byte)src)
	count := 0
	for {
		_, ok := scanner_next(&s)
		if !ok {
			break
		}
		count += 1
	}
	testing.expect_value(t, s.err.kind, Error_Kind.None)
	testing.expect(t, count > 20)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect(t, track.total_allocation_count == 0, "scanning must not allocate")
}
