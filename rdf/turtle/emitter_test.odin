package turtle

import "core:mem"
import "core:strings"
import "core:testing"

import rdf ".."

EX_PREFIXES := []Prefix{{"ex", "http://e/"}, {"xsd", "http://www.w3.org/2001/XMLSchema#"}}

emit_seq :: proc(prefixes: []Prefix, ts: []rdf.Triple) -> strings.Builder {
	b := strings.builder_make()
	w := strings.to_writer(&b)
	e: Emitter
	_ = emitter_init(&e, w, prefixes)
	defer emitter_destroy(&e)
	for t in ts {
		_ = emit(&e, t)
	}
	_ = emitter_finish(&e)
	return b
}

@(test)
test_emit_grouping_and_a :: proc(t: ^testing.T) {
	ts := []rdf.Triple {
		{subject = rdf.IRI("http://e/s"), predicate = rdf.IRI("http://e/p"), object = rdf.IRI("http://e/o1")},
		{subject = rdf.IRI("http://e/s"), predicate = rdf.IRI("http://e/p"), object = rdf.IRI("http://e/o2")},
		{subject = rdf.IRI("http://e/s"), predicate = rdf.RDF_TYPE, object = rdf.IRI("http://e/T")},
		{subject = rdf.IRI("http://e/t"), predicate = rdf.IRI("http://e/r"), object = rdf.literal_plain("x")},
	}
	b := emit_seq(EX_PREFIXES, ts)
	defer strings.builder_destroy(&b)

	expected := "@prefix ex: <http://e/> .\n" +
		"@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n" +
		"ex:s ex:p ex:o1 , ex:o2 ;\n" +
		"    a ex:T .\n" +
		"ex:t ex:r \"x\" .\n"
	testing.expect_value(t, strings.to_string(b), expected)
}

@(test)
test_emit_flat_without_prefixes :: proc(t: ^testing.T) {
	ts := []rdf.Triple {
		{subject = rdf.IRI("http://e/s"), predicate = rdf.RDF_TYPE, object = rdf.IRI("http://e/T")},
	}
	b := emit_seq(nil, ts)
	defer strings.builder_destroy(&b)
	testing.expect_value(
		t,
		strings.to_string(b),
		"<http://e/s> a <http://e/T> .\n",
	)
}

@(test)
test_emit_pname_edges :: proc(t: ^testing.T) {
	ts := []rdf.Triple {
		// Interior dots raw; trailing dot escaped.
		{subject = rdf.IRI("http://e/a.b"), predicate = rdf.IRI("http://e/p"), object = rdf.IRI("http://e/end.")},
		// Valid percent kept raw; bare '%' escaped; slash escaped.
		{subject = rdf.IRI("http://e/o%41x"), predicate = rdf.IRI("http://e/p"), object = rdf.IRI("http://e/o%zz")},
		{subject = rdf.IRI("http://e/a/b"), predicate = rdf.IRI("http://e/p"), object = rdf.IRI("http://e/")},
		// No prefix match and non-emittable locals fall back to <>.
		{subject = rdf.IRI("http://other.example/x"), predicate = rdf.IRI("http://e/p"), object = rdf.IRI("http://e/sp ce")},
	}
	b := emit_seq(EX_PREFIXES, ts)
	defer strings.builder_destroy(&b)

	expected := "@prefix ex: <http://e/> .\n" +
		"@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n" +
		"ex:a.b ex:p ex:end\\. .\n" +
		"ex:o%41x ex:p ex:o\\%zz .\n" +
		"ex:a\\/b ex:p ex: .\n" +
		"<http://other.example/x> ex:p <http://e/sp\\u0020ce> .\n"
	testing.expect_value(t, strings.to_string(b), expected)
}

@(test)
test_emit_literals_and_datatypes :: proc(t: ^testing.T) {
	ts := []rdf.Triple {
		{subject = rdf.IRI("http://e/s"), predicate = rdf.IRI("http://e/p"), object = rdf.literal_typed("42", rdf.XSD_INTEGER)},
		{subject = rdf.IRI("http://e/s"), predicate = rdf.IRI("http://e/p"), object = rdf.literal_lang("chat", "fr")},
		{subject = rdf.IRI("http://e/s"), predicate = rdf.IRI("http://e/p"), object = rdf.literal_dir_lang("chat", "fr", .RTL)},
	}
	b := emit_seq(EX_PREFIXES, ts)
	defer strings.builder_destroy(&b)

	expected := "@prefix ex: <http://e/> .\n" +
		"@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n" +
		"ex:s ex:p \"42\"^^xsd:integer , \"chat\"@fr , \"chat\"@fr--rtl .\n"
	testing.expect_value(t, strings.to_string(b), expected)
}

@(test)
test_emit_triple_term :: proc(t: ^testing.T) {
	inner := rdf.Triple{subject = rdf.IRI("http://e/a"), predicate = rdf.RDF_TYPE, object = rdf.literal_plain("x")}
	ts := []rdf.Triple {
		{subject = rdf.Blank_Node("r"), predicate = rdf.RDF_REIFIES, object = &inner},
	}
	b := emit_seq(EX_PREFIXES, ts)
	defer strings.builder_destroy(&b)

	expected := "@prefix ex: <http://e/> .\n" +
		"@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n" +
		"_:r <http://www.w3.org/1999/02/22-rdf-syntax-ns#reifies> <<( ex:a a \"x\" )>> .\n"
	testing.expect_value(t, strings.to_string(b), expected)
}

// Round trip: parse -> emit -> parse must yield the same statement
// sequence up to a blank-node bijection (the parser's label remapping
// makes exact labels unstable across a round trip by design).

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

parse_and_collect :: proc(t: ^testing.T, src: string, out: ^[dynamic]rdf.Triple, loc := #caller_location) {
	p: Parser
	parser_init(&p, transmute([]byte)src)
	defer parser_destroy(&p)
	for {
		tr, ok := parser_next(&p)
		if !ok {
			break
		}
		append(out, rdf.clone_triple(tr))
	}
	testing.expectf(t, p.err.kind == Error_Kind.None, "parse failed: %v at %d:%d", p.err.kind, p.err.line, p.err.column, loc = loc)
}

ROUND_TRIP_SRC :: `
	@prefix ex: <http://e/> .
	@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
	ex:s a ex:T ;
		ex:p "plain" , "esc\"q\nx" , 'single' , """long
line""" ;
		ex:q "chat"@fr--ltr , 42 , -4.2 , 1.5e3 , true ;
		ex:num "7"^^xsd:byte .
	_:doc ex:p ex:o.dots , ex:o%41x , <http://other.example/y> .
	[ ex:a ( 1 2 ) ] ex:b [ ] .
	ex:s2 ex:r ex:o {| ex:conf 0.9 |} .
	<< ex:x ex:y ex:z >> ex:said ex:w .
	ex:s3 ex:tt <<( ex:a ex:b "lit" )>> .
`

round_trip :: proc(t: ^testing.T, prefixes: []Prefix, loc := #caller_location) {
	originals: [dynamic]rdf.Triple
	defer {
		for tr in originals {
			rdf.destroy_triple(tr)
		}
		delete(originals)
	}
	parse_and_collect(t, ROUND_TRIP_SRC, &originals, loc)
	testing.expectf(t, len(originals) > 15, "corpus too small: %d", len(originals), loc = loc)

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	e: Emitter
	_ = emitter_init(&e, strings.to_writer(&b), prefixes)
	defer emitter_destroy(&e)
	for tr in originals {
		err := emit(&e, tr)
		testing.expect(t, err == nil, loc = loc)
	}
	_ = emitter_finish(&e)

	reparsed: [dynamic]rdf.Triple
	defer {
		for tr in reparsed {
			rdf.destroy_triple(tr)
		}
		delete(reparsed)
	}
	parse_and_collect(t, strings.to_string(b), &reparsed, loc)

	testing.expectf(t, len(reparsed) == len(originals), "count: %d -> %d\n%s", len(originals), len(reparsed), strings.to_string(b), loc = loc)
	if len(reparsed) != len(originals) {
		return
	}
	fwd: map[string]string
	bwd: map[string]string
	defer delete(fwd)
	defer delete(bwd)
	for tr, i in originals {
		re := reparsed[i]
		ok := term_match(tr.subject, re.subject, &fwd, &bwd) &&
			term_match(tr.predicate, re.predicate, &fwd, &bwd) &&
			term_match(tr.object, re.object, &fwd, &bwd)
		testing.expectf(t, ok, "statement %d differs: %v vs %v\n%s", i, tr, re, strings.to_string(b), loc = loc)
	}
}

@(test)
test_round_trip_prefixed :: proc(t: ^testing.T) {
	round_trip(t, EX_PREFIXES)
}

@(test)
test_emitter_steady_state_allocations :: proc(t: ^testing.T) {
	// The builder grows on the untracked allocator; only the emitter's
	// lookbehind buffers are tracked — they reach capacity and stop.
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	e: Emitter
	_ = emitter_init(&e, strings.to_writer(&b), EX_PREFIXES, mem.tracking_allocator(&track))
	defer emitter_destroy(&e)

	tr := rdf.Triple {
		subject   = rdf.IRI("http://e/subject-one"),
		predicate = rdf.IRI("http://e/p"),
		object    = rdf.literal_plain("x"),
	}
	other := rdf.Triple {
		subject   = rdf.IRI("http://e/subject-two"),
		predicate = rdf.IRI("http://e/q"),
		object    = rdf.literal_plain("y"),
	}
	_ = emit(&e, tr)
	_ = emit(&e, other)
	high_water := track.total_allocation_count
	for _ in 0 ..< 200 {
		_ = emit(&e, tr)
		_ = emit(&e, other)
	}
	_ = emitter_finish(&e)
	testing.expectf(
		t,
		track.total_allocation_count == high_water,
		"steady-state emission allocated: %v -> %v",
		high_water,
		track.total_allocation_count,
	)
}

@(test)
test_round_trip_flat :: proc(t: ^testing.T) {
	round_trip(t, nil)
}
