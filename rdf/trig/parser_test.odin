package trig

import "core:strings"
import "core:testing"

import rdf ".."

EX_PRE :: "@prefix ex: <http://e/> .\n"

ex :: proc(local: string) -> rdf.IRI {
	context.allocator = context.temp_allocator
	return rdf.IRI(strings.concatenate({"http://e/", local}))
}

next_expect :: proc(
	t: ^testing.T,
	p: ^Parser,
	s, pr, o: rdf.Term,
	g: rdf.Graph_Label,
	loc := #caller_location,
) {
	q, ok := parser_next(p)
	testing.expectf(t, ok, "missing quad (err %v)", p.err.kind, loc = loc)
	if !ok {
		return
	}
	testing.expectf(t, rdf.equal_term(q.subject, s), "subject: got %v, want %v", q.subject, s, loc = loc)
	testing.expectf(t, rdf.equal_term(q.predicate, pr), "predicate: got %v, want %v", q.predicate, pr, loc = loc)
	testing.expectf(t, rdf.equal_term(q.object, o), "object: got %v, want %v", q.object, o, loc = loc)
	testing.expectf(t, rdf.equal_graph_label(q.graph, g), "graph: got %v, want %v", q.graph, g, loc = loc)
}

expect_end :: proc(t: ^testing.T, p: ^Parser, loc := #caller_location) {
	_, ok := parser_next(p)
	testing.expectf(t, !ok, "expected end of input", loc = loc)
	testing.expectf(t, p.err.kind == Error_Kind.None, "err %v", p.err.kind, loc = loc)
}

expect_error :: proc(t: ^testing.T, src: string, kind: Error_Kind, loc := #caller_location) {
	p: Parser
	parser_init(&p, transmute([]byte)src)
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
test_default_graph_and_blocks :: proc(t: ^testing.T) {
	src := EX_PRE +
		"ex:s ex:p ex:o .\n" +
		"{ ex:a ex:b ex:c }\n" +
		"ex:g1 { ex:d ex:e ex:f . }\n" +
		"GRAPH ex:g2 { ex:h ex:i ex:j }\n" +
		"graph ex:g3 { ex:k ex:l ex:m . }\n" +
		"ex:tail ex:p ex:o .\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	next_expect(t, &p, ex("s"), ex("p"), ex("o"), nil)
	next_expect(t, &p, ex("a"), ex("b"), ex("c"), nil)
	next_expect(t, &p, ex("d"), ex("e"), ex("f"), ex("g1"))
	next_expect(t, &p, ex("h"), ex("i"), ex("j"), ex("g2"))
	next_expect(t, &p, ex("k"), ex("l"), ex("m"), ex("g3"))
	next_expect(t, &p, ex("tail"), ex("p"), ex("o"), nil)
	expect_end(t, &p)
}

@(test)
test_multiple_statements_in_block :: proc(t: ^testing.T) {
	// Statements inside a block are dot-separated; the final dot is
	// optional before '}'.
	src := EX_PRE + "ex:g { ex:a ex:b ex:c . ex:d ex:e ex:f }\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	next_expect(t, &p, ex("a"), ex("b"), ex("c"), ex("g"))
	next_expect(t, &p, ex("d"), ex("e"), ex("f"), ex("g"))
	expect_end(t, &p)
}

@(test)
test_blank_node_graph_labels :: proc(t: ^testing.T) {
	src := EX_PRE +
		"_:g { ex:a ex:b ex:c }\n" +
		"[] { ex:d ex:e ex:f }\n" +
		"GRAPH [] { ex:h ex:i ex:j }\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	next_expect(t, &p, ex("a"), ex("b"), ex("c"), rdf.Blank_Node("g"))
	next_expect(t, &p, ex("d"), ex("e"), ex("f"), rdf.Blank_Node("b0"))
	next_expect(t, &p, ex("h"), ex("i"), ex("j"), rdf.Blank_Node("b1"))
	expect_end(t, &p)
}

@(test)
test_empty_blocks :: proc(t: ^testing.T) {
	src := EX_PRE + "{ }\nex:g { }\nex:s ex:p ex:o .\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	next_expect(t, &p, ex("s"), ex("p"), ex("o"), nil)
	expect_end(t, &p)
}

@(test)
test_turtle_structures_inside_blocks :: proc(t: ^testing.T) {
	src := EX_PRE + "ex:g { ex:s ex:p [ ex:q ex:v ] , ( 1 ) ; ex:r ex:o ~ ex:rf }\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	b := proc(n: string) -> rdf.Term { return rdf.Blank_Node(n) }
	g := rdf.Graph_Label(ex("g"))
	one := rdf.literal_typed("1", rdf.XSD_INTEGER)
	next_expect(t, &p, b("b0"), ex("q"), ex("v"), g)
	next_expect(t, &p, ex("s"), ex("p"), b("b0"), g)
	next_expect(t, &p, b("b1"), rdf.RDF_FIRST, one, g)
	next_expect(t, &p, b("b1"), rdf.RDF_REST, rdf.RDF_NIL, g)
	next_expect(t, &p, ex("s"), ex("p"), b("b1"), g)
	next_expect(t, &p, ex("s"), ex("r"), ex("o"), g)
	tt := rdf.Triple{subject = ex("s"), predicate = ex("r"), object = ex("o")}
	next_expect(t, &p, ex("rf"), rdf.RDF_REIFIES, &tt, g)
	expect_end(t, &p)
}

@(test)
test_directives_between_blocks :: proc(t: ^testing.T) {
	src := "@prefix a: <http://one/> .\n" +
		"a:s a:p a:o .\n" +
		"@prefix a: <http://two/> .\n" +
		"GRAPH a:g { a:s a:p a:o }\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	one := rdf.IRI("http://one/s")
	next_expect(t, &p, one, rdf.IRI("http://one/p"), rdf.IRI("http://one/o"), nil)
	two := rdf.IRI("http://two/s")
	next_expect(t, &p, two, rdf.IRI("http://two/p"), rdf.IRI("http://two/o"), rdf.IRI("http://two/g"))
	expect_end(t, &p)
}

@(test)
test_anon_counter_shared_across_graphs :: proc(t: ^testing.T) {
	src := EX_PRE + "ex:g { ex:s ex:p [ ] . }\n[ ] ex:q ex:v .\n"
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)

	next_expect(t, &p, ex("s"), ex("p"), rdf.Blank_Node("b0"), ex("g"))
	next_expect(t, &p, rdf.Blank_Node("b1"), ex("q"), ex("v"), nil)
	expect_end(t, &p)
}

@(test)
test_trig_errors :: proc(t: ^testing.T) {
	expect_error(t, EX_PRE + "ex:g { ex:a ex:b ex:c .", .Unclosed_Graph)
	expect_error(t, EX_PRE + "ex:g { ex:a ex:b ex:c ", .Unclosed_Graph)
	expect_error(t, EX_PRE + "GRAPH ex:g ex:a ex:b ex:c .", .Expected_Graph_Block)
	expect_error(t, EX_PRE + "GRAPH \"lit\" { }", .Invalid_Graph_Label)
	// Nested graph blocks are not a thing.
	expect_error(t, EX_PRE + "ex:g { ex:g2 { ex:a ex:b ex:c } }", .Expected_Predicate)
	// A non-empty property list cannot be a graph label.
	expect_error(t, EX_PRE + "[ ex:p ex:o ] { }", .Expected_Predicate)
	// Stray close brace.
	expect_error(t, EX_PRE + "} ex:s ex:p ex:o .", .Expected_Subject)
}
