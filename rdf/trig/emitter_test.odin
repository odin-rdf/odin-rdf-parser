package trig

import "core:strings"
import "core:testing"

import rdf ".."

EX_PREFIXES := []Prefix{{"ex", "http://e/"}}

@(test)
test_emit_graph_blocks_exact :: proc(t: ^testing.T) {
	qs := []rdf.Quad {
		{triple = {rdf.IRI("http://e/s"), rdf.IRI("http://e/p"), rdf.IRI("http://e/o")}, graph = nil},
		{triple = {rdf.IRI("http://e/a"), rdf.IRI("http://e/b"), rdf.IRI("http://e/c1")}, graph = rdf.IRI("http://e/g")},
		{triple = {rdf.IRI("http://e/a"), rdf.IRI("http://e/b"), rdf.IRI("http://e/c2")}, graph = rdf.IRI("http://e/g")},
		{triple = {rdf.IRI("http://e/d"), rdf.RDF_TYPE, rdf.IRI("http://e/T")}, graph = rdf.IRI("http://e/g")},
		{triple = {rdf.IRI("http://e/x"), rdf.IRI("http://e/y"), rdf.IRI("http://e/z")}, graph = rdf.Blank_Node("g2")},
		{triple = {rdf.IRI("http://e/tail"), rdf.IRI("http://e/p"), rdf.IRI("http://e/o")}, graph = nil},
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	e: Emitter
	_ = emitter_init(&e, strings.to_writer(&b), EX_PREFIXES)
	defer emitter_destroy(&e)
	for q in qs {
		err := emit(&e, q)
		testing.expect(t, err == nil)
	}
	_ = emitter_finish(&e)

	expected := "@prefix ex: <http://e/> .\n" +
		"ex:s ex:p ex:o .\n" +
		"ex:g {\n" +
		"  ex:a ex:b ex:c1 , ex:c2 .\n" +
		"  ex:d a ex:T .\n" +
		"}\n" +
		"_:g2 {\n" +
		"  ex:x ex:y ex:z .\n" +
		"}\n" +
		"ex:tail ex:p ex:o .\n"
	testing.expect_value(t, strings.to_string(b), expected)
}

term_match :: proc(a, b: rdf.Term, fwd, bwd: ^map[string]string) -> bool {
	#partial switch va in a {
	case rdf.Blank_Node:
		vb, is_blank := b.(rdf.Blank_Node)
		if !is_blank {
			return false
		}
		la, lb := string(va), string(vb)
		if mapped, has := fwd[la]; has {
			return mapped == lb
		}
		if _, taken := bwd[lb]; taken {
			return false
		}
		fwd[la] = lb
		bwd[lb] = la
		return true
	case ^rdf.Triple:
		vb, is_tt := b.(^rdf.Triple)
		if !is_tt {
			return false
		}
		return term_match(va.subject, vb.subject, fwd, bwd) &&
			term_match(va.predicate, vb.predicate, fwd, bwd) &&
			term_match(va.object, vb.object, fwd, bwd)
	}
	return rdf.equal_term(a, b)
}

graph_match :: proc(a, b: rdf.Graph_Label, fwd, bwd: ^map[string]string) -> bool {
	switch va in a {
	case rdf.IRI:
		vb, is_iri := b.(rdf.IRI)
		return is_iri && va == vb
	case rdf.Blank_Node:
		return term_match(va, b.(rdf.Blank_Node) or_else rdf.Blank_Node(""), fwd, bwd)
	}
	return b == nil
}

@(test)
test_round_trip_with_graphs :: proc(t: ^testing.T) {
	src := `
		@prefix ex: <http://e/> .
		ex:s ex:p ex:o , 42 .
		ex:g { ex:a ex:b [ ex:q ( 1 2 ) ] . ex:a ex:c "x"@en }
		_:bg { ex:d ex:e <<( ex:f ex:h "lit" )>> }
		GRAPH ex:g2 { ex:i ex:j ex:k ~ ex:rf }
		ex:tail ex:p ex:o .
	`
	originals: [dynamic]rdf.Quad
	defer {
		for q in originals {
			rdf.destroy_quad(q)
		}
		delete(originals)
	}
	{
		p: Parser
		parser_init(&p, transmute([]byte)src)
		defer parser_destroy(&p)
		for {
			q, ok := parser_next(&p)
			if !ok {
				break
			}
			append(&originals, rdf.clone_quad(q))
		}
		testing.expectf(t, p.err.kind == Error_Kind.None, "parse failed: %v", p.err.kind)
	}
	testing.expectf(t, len(originals) > 8, "corpus too small: %d", len(originals))

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	e: Emitter
	_ = emitter_init(&e, strings.to_writer(&b), EX_PREFIXES)
	defer emitter_destroy(&e)
	for q in originals {
		err := emit(&e, q)
		testing.expect(t, err == nil)
	}
	_ = emitter_finish(&e)

	reparsed: [dynamic]rdf.Quad
	defer {
		for q in reparsed {
			rdf.destroy_quad(q)
		}
		delete(reparsed)
	}
	{
		p: Parser
		parser_init(&p, transmute([]byte)strings.to_string(b))
		defer parser_destroy(&p)
		for {
			q, ok := parser_next(&p)
			if !ok {
				break
			}
			append(&reparsed, rdf.clone_quad(q))
		}
		testing.expectf(t, p.err.kind == Error_Kind.None, "reparse failed: %v\n%s", p.err.kind, strings.to_string(b))
	}

	testing.expectf(t, len(reparsed) == len(originals), "count: %d -> %d\n%s", len(originals), len(reparsed), strings.to_string(b))
	if len(reparsed) != len(originals) {
		return
	}
	fwd: map[string]string
	bwd: map[string]string
	defer delete(fwd)
	defer delete(bwd)
	for q, i in originals {
		re := reparsed[i]
		ok := term_match(q.subject, re.subject, &fwd, &bwd) &&
			term_match(q.predicate, re.predicate, &fwd, &bwd) &&
			term_match(q.object, re.object, &fwd, &bwd) &&
			graph_match(q.graph, re.graph, &fwd, &bwd)
		testing.expectf(t, ok, "statement %d differs: %v vs %v\n%s", i, q, re, strings.to_string(b))
	}
}
