package turtle

import "core:mem"
import "core:strings"
import "core:testing"

import rdf ".."

EX_PRE :: "@prefix ex: <http://e/> .\n"

ex :: proc(local: string) -> rdf.IRI {
	context.allocator = context.temp_allocator
	return rdf.IRI(strings.concatenate({"http://e/", local}))
}

next_expect :: proc(t: ^testing.T, p: ^Parser, s, pr, o: rdf.Term, loc := #caller_location) {
	tr, ok := parser_next(p)
	testing.expectf(t, ok, "missing triple (err %v)", p.err.kind, loc = loc)
	if !ok {
		return
	}
	testing.expectf(t, rdf.equal_term(tr.subject, s), "subject: got %v, want %v", tr.subject, s, loc = loc)
	testing.expectf(t, rdf.equal_term(tr.predicate, pr), "predicate: got %v, want %v", tr.predicate, pr, loc = loc)
	testing.expectf(t, rdf.equal_term(tr.object, o), "object: got %v, want %v", tr.object, o, loc = loc)
}

expect_end :: proc(t: ^testing.T, p: ^Parser, loc := #caller_location) {
	_, ok := parser_next(p)
	testing.expectf(t, !ok, "expected end of input", loc = loc)
	testing.expectf(t, p.err.kind == Error_Kind.None, "err %v", p.err.kind, loc = loc)
}

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
test_predicate_and_object_lists :: proc(t: ^testing.T) {
	src := EX_PRE + "ex:s ex:p1 ex:o1 ; ex:p2 ex:o2 , ex:o3 ;; ex:p3 ex:o4 ; .\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	next_expect(t, &p, ex("s"), ex("p1"), ex("o1"))
	next_expect(t, &p, ex("s"), ex("p2"), ex("o2"))
	next_expect(t, &p, ex("s"), ex("p2"), ex("o3"))
	next_expect(t, &p, ex("s"), ex("p3"), ex("o4"))
	expect_end(t, &p)
}

@(test)
test_numeric_and_boolean_literals :: proc(t: ^testing.T) {
	src := EX_PRE + "ex:s ex:p 42 , -4.2 , 1.5e3 , true , false .\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	next_expect(t, &p, ex("s"), ex("p"), rdf.literal_typed("42", rdf.XSD_INTEGER))
	next_expect(t, &p, ex("s"), ex("p"), rdf.literal_typed("-4.2", rdf.XSD_DECIMAL))
	next_expect(t, &p, ex("s"), ex("p"), rdf.literal_typed("1.5e3", rdf.XSD_DOUBLE))
	next_expect(t, &p, ex("s"), ex("p"), rdf.literal_typed("true", rdf.XSD_BOOLEAN))
	next_expect(t, &p, ex("s"), ex("p"), rdf.literal_typed("false", rdf.XSD_BOOLEAN))
	expect_end(t, &p)
}

@(test)
test_anon_blank_nodes :: proc(t: ^testing.T) {
	src := EX_PRE + "[ ] ex:p ex:o .\nex:s ex:q [ ] .\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	next_expect(t, &p, rdf.Blank_Node("b0"), ex("p"), ex("o"))
	next_expect(t, &p, ex("s"), ex("q"), rdf.Blank_Node("b1"))
	expect_end(t, &p)
}

@(test)
test_bnode_property_lists :: proc(t: ^testing.T) {
	// Nested-structure triples precede the triple referencing the node.
	src := EX_PRE +
		"ex:s ex:p [ ex:q ex:v ] .\n" +
		"[ ex:a ex:b ] .\n" +
		"[ ex:c ex:d ] ex:e ex:f .\n" +
		"[ ex:g [ ex:h ex:i ] ] .\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	b := proc(n: string) -> rdf.Term { return rdf.Blank_Node(n) }
	next_expect(t, &p, b("b0"), ex("q"), ex("v"))
	next_expect(t, &p, ex("s"), ex("p"), b("b0"))
	next_expect(t, &p, b("b1"), ex("a"), ex("b"))
	next_expect(t, &p, b("b2"), ex("c"), ex("d"))
	next_expect(t, &p, b("b2"), ex("e"), ex("f"))
	next_expect(t, &p, b("b4"), ex("h"), ex("i"))
	next_expect(t, &p, b("b3"), ex("g"), b("b4"))
	expect_end(t, &p)
}

@(test)
test_collections :: proc(t: ^testing.T) {
	src := EX_PRE + "ex:s ex:p ( ex:a ex:b ) .\nex:s ex:q () .\n() ex:r ex:o .\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	b := proc(n: string) -> rdf.Term { return rdf.Blank_Node(n) }
	next_expect(t, &p, b("b0"), rdf.RDF_FIRST, ex("a"))
	next_expect(t, &p, b("b0"), rdf.RDF_REST, b("b1"))
	next_expect(t, &p, b("b1"), rdf.RDF_FIRST, ex("b"))
	next_expect(t, &p, b("b1"), rdf.RDF_REST, rdf.RDF_NIL)
	next_expect(t, &p, ex("s"), ex("p"), b("b0"))
	next_expect(t, &p, ex("s"), ex("q"), rdf.RDF_NIL)
	next_expect(t, &p, rdf.RDF_NIL, ex("r"), ex("o"))
	expect_end(t, &p)
}

@(test)
test_nested_collection :: proc(t: ^testing.T) {
	src := EX_PRE + "ex:s ex:p ( 1 ( 2 ) ) .\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	b := proc(n: string) -> rdf.Term { return rdf.Blank_Node(n) }
	one := rdf.literal_typed("1", rdf.XSD_INTEGER)
	two := rdf.literal_typed("2", rdf.XSD_INTEGER)
	next_expect(t, &p, b("b0"), rdf.RDF_FIRST, one)
	// The inner collection's chain (cell b1) is emitted while it is
	// parsed as the second element, before the outer rest-link (b2).
	next_expect(t, &p, b("b1"), rdf.RDF_FIRST, two)
	next_expect(t, &p, b("b1"), rdf.RDF_REST, rdf.RDF_NIL)
	next_expect(t, &p, b("b0"), rdf.RDF_REST, b("b2"))
	next_expect(t, &p, b("b2"), rdf.RDF_FIRST, b("b1"))
	next_expect(t, &p, b("b2"), rdf.RDF_REST, rdf.RDF_NIL)
	next_expect(t, &p, ex("s"), ex("p"), b("b0"))
	expect_end(t, &p)
}

@(test)
test_deep_nesting_bounded :: proc(t: ^testing.T) {
	depth := 200
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)
	strings.write_string(&b, EX_PRE)
	strings.write_string(&b, "ex:s ex:p ")
	for _ in 0 ..< depth {
		strings.write_string(&b, "[ ex:q ")
	}
	strings.write_string(&b, "ex:o")
	for _ in 0 ..< depth {
		strings.write_string(&b, " ]")
	}
	strings.write_string(&b, " .")

	p: Parser
	parser_init(&p, transmute([]byte)strings.to_string(b))
	defer parser_destroy(&p)
	for {
		_, ok := parser_next(&p)
		if !ok {
			break
		}
	}
	testing.expect_value(t, p.err.kind, Error_Kind.Nesting_Too_Deep)
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
test_steady_state_allocations :: proc(t: ^testing.T) {
	original := context.allocator
	b: strings.Builder
	strings.builder_init(&b, original)
	defer strings.builder_destroy(&b)
	strings.write_string(&b, EX_PRE)
	for _ in 0 ..< 200 {
		strings.write_string(&b, "ex:s ex:p ex:o1 , ex:o2 ; ex:q ex:o3 .\n")
	}
	src := strings.to_string(b)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, original)
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	p: Parser
	parser_init(&p, transmute([]byte)src, "", allocator)
	defer parser_destroy(&p)

	// Drain the first statement (3 triples) plus one triple of the
	// second: queue and intern table are now at their high-water mark.
	for _ in 0 ..< 4 {
		_, ok := parser_next(&p)
		testing.expect(t, ok)
	}
	high_water := track.total_allocation_count
	count := 4
	for {
		_, ok := parser_next(&p)
		if !ok {
			break
		}
		count += 1
	}
	testing.expect_value(t, p.err.kind, Error_Kind.None)
	testing.expect_value(t, count, 600)
	testing.expectf(
		t,
		track.total_allocation_count == high_water,
		"steady-state parsing allocated: %v -> %v",
		high_water,
		track.total_allocation_count,
	)
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
