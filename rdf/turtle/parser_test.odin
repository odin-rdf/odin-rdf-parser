package turtle

import "core:testing"

import rdf ".."

expect_error :: proc(t: ^testing.T, src: string, kind: Error_Kind, base := "", loc := #caller_location) {
	p: Parser
	parser_init(&p, transmute([]byte)src, base)
	defer parser_destroy(&p)
	for {
		_, ok := parser_next(&p)
		if !ok {
			break
		}
	}
	testing.expectf(t, p.err.kind == kind, "%q: got %v, want %v", src, p.err.kind, kind, loc = loc)
}

@(test)
test_directives_and_simple_triples :: proc(t: ^testing.T) {
	src := `
		@prefix foaf: <http://xmlns.com/foaf/0.1/> .
		PREFIX ex: <http://example.org/ns#>
		@base <http://example.org/base/> .
		foaf:alice a foaf:Person .
		ex:s ex:p <relative> .
		<http://abs.example/x> foaf:knows foaf:bob .
	`
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	t1, ok1 := parser_next(&p)
	testing.expect(t, ok1)
	testing.expect_value(t, t1.subject.(rdf.IRI), rdf.IRI("http://xmlns.com/foaf/0.1/alice"))
	testing.expect_value(t, t1.predicate.(rdf.IRI), rdf.RDF_TYPE)
	testing.expect_value(t, t1.object.(rdf.IRI), rdf.IRI("http://xmlns.com/foaf/0.1/Person"))

	t2, ok2 := parser_next(&p)
	testing.expect(t, ok2)
	testing.expect_value(t, t2.subject.(rdf.IRI), rdf.IRI("http://example.org/ns#s"))
	testing.expect_value(t, t2.object.(rdf.IRI), rdf.IRI("http://example.org/base/relative"))

	t3, ok3 := parser_next(&p)
	testing.expect(t, ok3)
	testing.expect_value(t, t3.subject.(rdf.IRI), rdf.IRI("http://abs.example/x"))

	_, ok4 := parser_next(&p)
	testing.expect(t, !ok4)
	testing.expect_value(t, p.err.kind, Error_Kind.None)
}

@(test)
test_initial_base_parameter :: proc(t: ^testing.T) {
	src := `<> <#p> <other> .`
	p: Parser
	parser_init(&p, transmute([]byte)src, "http://example.org/dir/doc")
	defer parser_destroy(&p)

	tr, ok := parser_next(&p)
	testing.expect(t, ok)
	testing.expect_value(t, tr.subject.(rdf.IRI), rdf.IRI("http://example.org/dir/doc"))
	testing.expect_value(t, tr.predicate.(rdf.IRI), rdf.IRI("http://example.org/dir/doc#p"))
	testing.expect_value(t, tr.object.(rdf.IRI), rdf.IRI("http://example.org/dir/other"))
}

@(test)
test_base_chaining_in_document :: proc(t: ^testing.T) {
	src := `
		@base <http://example.org/dir/> .
		@base <sub/> .
		<x> <p> <../up> .
	`
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	tr, ok := parser_next(&p)
	testing.expect(t, ok)
	testing.expect_value(t, tr.subject.(rdf.IRI), rdf.IRI("http://example.org/dir/sub/x"))
	testing.expect_value(t, tr.object.(rdf.IRI), rdf.IRI("http://example.org/dir/up"))
}

@(test)
test_prefix_redeclaration_overrides :: proc(t: ^testing.T) {
	src := `
		@prefix p: <http://one.example/> .
		p:a p:b p:c .
		@prefix p: <http://two.example/> .
		p:a p:b p:c .
	`
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	t1, _ := parser_next(&p)
	testing.expect_value(t, t1.subject.(rdf.IRI), rdf.IRI("http://one.example/a"))
	t2, ok := parser_next(&p)
	testing.expect(t, ok)
	testing.expect_value(t, t2.subject.(rdf.IRI), rdf.IRI("http://two.example/a"))
}

@(test)
test_pname_local_forms :: proc(t: ^testing.T) {
	// Escaped locals, percent encodings (kept raw), colons in locals,
	// the default prefix, and empty locals.
	src := `
		@prefix : <http://ex.org/> .
		@prefix ex: <http://ex.org/ns#> .
		:s ex:p\~x :o .
		: ex:%41B ex:a:b .
	`
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	t1, ok1 := parser_next(&p)
	testing.expect(t, ok1)
	testing.expect_value(t, t1.subject.(rdf.IRI), rdf.IRI("http://ex.org/s"))
	testing.expect_value(t, t1.predicate.(rdf.IRI), rdf.IRI("http://ex.org/ns#p~x"))
	testing.expect_value(t, t1.object.(rdf.IRI), rdf.IRI("http://ex.org/o"))

	t2, ok2 := parser_next(&p)
	testing.expect(t, ok2)
	testing.expect_value(t, t2.subject.(rdf.IRI), rdf.IRI("http://ex.org/"))
	testing.expect_value(t, t2.predicate.(rdf.IRI), rdf.IRI("http://ex.org/ns#%41B"))
	testing.expect_value(t, t2.object.(rdf.IRI), rdf.IRI("http://ex.org/ns#a:b"))
}

@(test)
test_interning_one_materialization :: proc(t: ^testing.T) {
	// The same prefixed name in different statements must expand to the
	// SAME backing storage — one materialization per distinct IRI.
	src := `
		@prefix ex: <http://ex.org/> .
		ex:s ex:p ex:o .
		ex:s2 ex:p ex:o .
	`
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	t1, _ := parser_next(&p)
	p1 := t1.predicate.(rdf.IRI)
	t2, ok := parser_next(&p)
	testing.expect(t, ok)
	p2 := t2.predicate.(rdf.IRI)
	testing.expect_value(t, p1, p2)
	testing.expect(
		t,
		raw_data(string(p1)) == raw_data(string(p2)),
		"same pname must intern to the same backing storage",
	)
}

@(test)
test_literals :: proc(t: ^testing.T) {
	src := `
		@prefix ex: <http://ex.org/> .
		ex:s ex:p "plain" .
		ex:s ex:p 'single' .
		ex:s ex:p "esc\n" .
		ex:s ex:p "chat"@fr .
		ex:s ex:p "chat"@fr--ltr .
		ex:s ex:p "42"^^<http://www.w3.org/2001/XMLSchema#integer> .
		ex:s ex:p "43"^^ex:dt .
	`
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	want := [?]rdf.Literal {
		rdf.literal_plain("plain"),
		rdf.literal_plain("single"),
		rdf.literal_plain("esc\n"),
		rdf.literal_lang("chat", "fr"),
		rdf.literal_dir_lang("chat", "fr", .LTR),
		rdf.literal_typed("42", "http://www.w3.org/2001/XMLSchema#integer"),
		rdf.literal_typed("43", "http://ex.org/dt"),
	}
	for w, i in want {
		tr, ok := parser_next(&p)
		testing.expectf(t, ok, "statement %d missing (err %v)", i, p.err.kind)
		got := tr.object.(rdf.Literal)
		testing.expectf(t, rdf.equal_term(got, w), "statement %d: got %v, want %v", i, got, w)
	}
}

@(test)
test_blank_node_labels :: proc(t: ^testing.T) {
	// Document labels are preserved — except labels in the synthesized
	// namespace (^B*b[0-9]+$), which get a 'B' prepended.
	src := `
		@prefix ex: <http://ex.org/> .
		_:alice ex:p _:b0 .
		_:Bb1 ex:p _:c1 .
	`
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	t1, _ := parser_next(&p)
	testing.expect_value(t, t1.subject.(rdf.Blank_Node), rdf.Blank_Node("alice"))
	testing.expect_value(t, t1.object.(rdf.Blank_Node), rdf.Blank_Node("Bb0"))
	t2, ok := parser_next(&p)
	testing.expect(t, ok)
	testing.expect_value(t, t2.subject.(rdf.Blank_Node), rdf.Blank_Node("BBb1"))
	testing.expect_value(t, t2.object.(rdf.Blank_Node), rdf.Blank_Node("c1"))
}

@(test)
test_long_strings_pass_through :: proc(t: ^testing.T) {
	src := "<http://e/s> <http://e/p> \"\"\"multi\nline\"\"\" ."
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)
	tr, ok := parser_next(&p)
	testing.expect(t, ok)
	testing.expect_value(t, tr.object.(rdf.Literal).lexical, "multi\nline")
}

@(test)
test_parser_errors :: proc(t: ^testing.T) {
	expect_error(t, `ex:s ex:p ex:o .`, .Undefined_Prefix)
	expect_error(t, `<http://e/s> <http://e/p> <rel> .`, .Relative_IRI)
	// A bare 'ex' (no colon) dies in the scanner as an unknown keyword.
	expect_error(t, `@prefix ex <http://e/> .`, .Unknown_Keyword)
	expect_error(t, `@prefix ex:name <http://e/> .`, .Expected_Prefix_Name)
	expect_error(t, `@prefix ex: "no" .`, .Expected_IRI)
	expect_error(t, `@base "no" .`, .Expected_IRI)
	expect_error(t, `@prefix ex: <http://e/>`, .Expected_Dot)
	expect_error(t, `<http://e/s> <http://e/p> <http://e/o>`, .Expected_Dot)
	expect_error(t, `<http://e/s> <http://e/p> .`, .Expected_Object)
	expect_error(t, `<http://e/s> .`, .Expected_Predicate)
	expect_error(t, `"literal" <http://e/p> <http://e/o> .`, .Expected_Subject)
	expect_error(t, `<http://e/s> "lit" <http://e/o> .`, .Expected_Predicate)
	expect_error(
		t,
		`<http://e/s> <http://e/p> "x"^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#langString> .`,
		.Reserved_Datatype,
	)
	// Relative initial base is rejected at init.
	expect_error(t, `<http://e/s> <http://e/p> <http://e/o> .`, .Relative_IRI, "not-absolute")
}

@(test)
test_error_positions :: proc(t: ^testing.T) {
	src := "@prefix ex: <http://e/> .\nex:s nope:p ex:o ."
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)
	for {
		_, ok := parser_next(&p)
		if !ok {
			break
		}
	}
	testing.expect_value(t, p.err.kind, Error_Kind.Undefined_Prefix)
	testing.expect_value(t, p.err.line, 2)
	testing.expect_value(t, p.err.column, 6)
}

@(test)
test_sticky_errors :: proc(t: ^testing.T) {
	src := `nope:s <http://e/p> <http://e/o> . <http://e/s2> <http://e/p2> <http://e/o2> .`
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)
	_, ok := parser_next(&p)
	testing.expect(t, !ok)
	testing.expect_value(t, p.err.kind, Error_Kind.Undefined_Prefix)
	_, ok2 := parser_next(&p)
	testing.expect(t, !ok2, "errors must be sticky")
}
