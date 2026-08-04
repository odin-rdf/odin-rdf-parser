package w3c

import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import rdf "../../../rdf"
import scan "../../../rdf/internal/scanner"
import quads "../../../rdf/quads"
import trig "../../../rdf/trig"
import triples "../../../rdf/triples"
import turtle "../../../rdf/turtle"

SUITE_ROOT :: #directory + ".."

Format :: enum {
	N_Triples,
	N_Quads,
	Turtle,
	TriG,
}

@(test)
test_w3c_rdf11_ntriples :: proc(t: ^testing.T) {
	run_suite(t, "rdf11-ntriples", .N_Triples, "", 70)
}

@(test)
test_w3c_rdf11_nquads :: proc(t: ^testing.T) {
	run_suite(t, "rdf11-nquads", .N_Quads, "", 87)
}

@(test)
test_w3c_rdf12_ntriples :: proc(t: ^testing.T) {
	run_suite(t, "rdf12-ntriples-syntax", .N_Triples, "", 29)
}

@(test)
test_w3c_rdf12_nquads :: proc(t: ^testing.T) {
	run_suite(t, "rdf12-nquads-syntax", .N_Quads, "", 27)
}

@(test)
test_w3c_rdf11_turtle :: proc(t: ^testing.T) {
	run_suite(t, "rdf11-turtle", .Turtle, "https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-turtle/", 313)
}

@(test)
test_w3c_rdf11_trig :: proc(t: ^testing.T) {
	run_suite(t, "rdf11-trig", .TriG, "https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-trig/", 356)
}

@(test)
test_w3c_rdf12_turtle_syntax :: proc(t: ^testing.T) {
	run_suite(t, "rdf12-turtle-syntax", .Turtle, "https://w3c.github.io/rdf-tests/rdf/rdf12/rdf-turtle/syntax/", 74)
}

@(test)
test_w3c_rdf12_turtle_eval :: proc(t: ^testing.T) {
	run_suite(t, "rdf12-turtle-eval", .Turtle, "https://w3c.github.io/rdf-tests/rdf/rdf12/rdf-turtle/eval/", 29)
}

@(test)
test_w3c_rdf12_trig_syntax :: proc(t: ^testing.T) {
	run_suite(t, "rdf12-trig-syntax", .TriG, "https://w3c.github.io/rdf-tests/rdf/rdf12/rdf-trig/syntax/", 35)
}

@(test)
test_w3c_rdf12_trig_eval :: proc(t: ^testing.T) {
	run_suite(t, "rdf12-trig-eval", .TriG, "https://w3c.github.io/rdf-tests/rdf/rdf12/rdf-trig/eval/", 25)
}

// run_suite runs every manifest entry. base is the suite's
// mf:assumedTestBase; each test's base IRI is base + action, per the
// W3C convention. expected_count pins the entry count recorded when the
// suite first passed — the guard against a manifest-reader regression
// silently dropping tests (RDF-T-0020).
run_suite :: proc(t: ^testing.T, suite: string, format: Format, base: string, expected_count: int) {
	manifest_path, _ := filepath.join({SUITE_ROOT, suite, "manifest.ttl"})
	defer delete(manifest_path)
	manifest_data, manifest_err := os.read_entire_file(manifest_path, context.allocator)
	if !testing.expectf(t, manifest_err == nil, "cannot read manifest %s: %v", manifest_path, manifest_err) {
		return
	}
	defer delete(manifest_data)

	entries := parse_manifest(string(manifest_data))
	defer destroy_entries(&entries)
	testing.expectf(
		t,
		len(entries) == expected_count,
		"%s: manifest yielded %d entries, expected %d — reader regression?",
		suite,
		len(entries),
		expected_count,
	)

	passed := 0
	for e in entries {
		kind: enum {
			Positive,
			Negative,
			Eval,
		}
		switch {
		case strings.contains(e.type_str, "PositiveSyntax"):
			kind = .Positive
		case strings.contains(e.type_str, "NegativeSyntax"), strings.contains(e.type_str, "NegativeEval"):
			// Negative eval failures for these formats are all detected
			// at parse time (bad IRIs, unresolvable relative references).
			kind = .Negative
		case strings.contains(e.type_str, "Eval"):
			kind = .Eval
		case:
			testing.expectf(t, false, "%s: unhandled test type %q — nothing may be silently skipped", e.id, e.type_str)
			continue
		}

		path, _ := filepath.join({SUITE_ROOT, suite, e.action})
		content, read_err := os.read_entire_file(path, context.allocator)
		delete(path)
		if !testing.expectf(t, read_err == nil, "%s: cannot read action file %q: %v", e.id, e.action, read_err) {
			continue
		}
		defer delete(content)

		test_base := strings.concatenate({base, e.action}) if base != "" else ""
		defer delete(test_base)

		switch kind {
		case .Positive:
			err := parse_document(content, format, test_base)
			if testing.expectf(
				t,
				err.kind == .None,
				"%s (%s): should parse, got %s at %d:%d",
				e.id,
				e.name,
				scan.error_message(err.kind),
				err.line,
				err.column,
			) {
				passed += 1
			}
		case .Negative:
			err := parse_document(content, format, test_base)
			if testing.expectf(t, err.kind != .None, "%s (%s): malformed document was accepted", e.id, e.name) {
				passed += 1
			}
		case .Eval:
			if run_eval(t, suite, format, e, content, test_base) {
				passed += 1
			}
		}
	}
	log.infof("%s: %d/%d conformance tests passed", suite, passed, len(entries))
}

// run_eval parses the action, parses the expected N-Triples/N-Quads
// result with the line-based parsers, and compares up to blank-node
// bijection.
run_eval :: proc(t: ^testing.T, suite: string, format: Format, e: Entry, content: []byte, test_base: string) -> bool {
	if !testing.expectf(t, e.result != "", "%s: eval test without mf:result", e.id) {
		return false
	}

	actual: [dynamic]rdf.Quad
	defer destroy_statements(&actual)
	err := parse_collect(content, format, test_base, &actual)
	if !testing.expectf(
		t,
		err.kind == .None,
		"%s (%s): should parse, got %s at %d:%d",
		e.id,
		e.name,
		scan.error_message(err.kind),
		err.line,
		err.column,
	) {
		return false
	}

	result_path, _ := filepath.join({SUITE_ROOT, suite, e.result})
	result_data, read_err := os.read_entire_file(result_path, context.allocator)
	delete(result_path)
	if !testing.expectf(t, read_err == nil, "%s: cannot read result file %q: %v", e.id, e.result, read_err) {
		return false
	}
	defer delete(result_data)

	expected: [dynamic]rdf.Quad
	defer destroy_statements(&expected)
	result_format := Format.N_Quads if format == .TriG else Format.N_Triples
	rerr := parse_collect(result_data, result_format, "", &expected)
	if !testing.expectf(
		t,
		rerr.kind == .None,
		"%s: expected-result file %q failed to parse: %s at %d:%d",
		e.id,
		e.result,
		scan.error_message(rerr.kind),
		rerr.line,
		rerr.column,
	) {
		return false
	}

	return testing.expectf(
		t,
		graphs_isomorphic(actual[:], expected[:]),
		"%s (%s): parsed dataset (%d statements) is not isomorphic to %s (%d statements)",
		e.id,
		e.name,
		len(actual),
		e.result,
		len(expected),
	)
}

parse_document :: proc(source: []byte, format: Format, base: string) -> scan.Error {
	switch format {
	case .N_Triples:
		p: triples.Parser
		triples.parser_init(&p, source)
		defer triples.parser_destroy(&p)
		for {
			_, ok := triples.parser_next(&p)
			if !ok {
				break
			}
		}
		return p.err
	case .N_Quads:
		p: quads.Parser
		quads.parser_init(&p, source)
		defer quads.parser_destroy(&p)
		for {
			_, ok := quads.parser_next(&p)
			if !ok {
				break
			}
		}
		return p.err
	case .Turtle:
		p: turtle.Parser
		turtle.parser_init(&p, source, base)
		defer turtle.parser_destroy(&p)
		for {
			_, ok := turtle.parser_next(&p)
			if !ok {
				break
			}
		}
		return p.err
	case .TriG:
		p: trig.Parser
		trig.parser_init(&p, source, base)
		defer trig.parser_destroy(&p)
		for {
			_, ok := trig.parser_next(&p)
			if !ok {
				break
			}
		}
		return p.err
	}
	return {}
}

// parse_collect parses a document into cloned statements (triples lift
// to default-graph quads).
parse_collect :: proc(source: []byte, format: Format, base: string, out: ^[dynamic]rdf.Quad) -> scan.Error {
	switch format {
	case .N_Triples:
		p: triples.Parser
		triples.parser_init(&p, source)
		defer triples.parser_destroy(&p)
		for {
			tr, ok := triples.parser_next(&p)
			if !ok {
				break
			}
			append(out, rdf.clone_quad(rdf.Quad{triple = tr}))
		}
		return p.err
	case .N_Quads:
		p: quads.Parser
		quads.parser_init(&p, source)
		defer quads.parser_destroy(&p)
		for {
			q, ok := quads.parser_next(&p)
			if !ok {
				break
			}
			append(out, rdf.clone_quad(q))
		}
		return p.err
	case .Turtle:
		p: turtle.Parser
		turtle.parser_init(&p, source, base)
		defer turtle.parser_destroy(&p)
		for {
			tr, ok := turtle.parser_next(&p)
			if !ok {
				break
			}
			append(out, rdf.clone_quad(rdf.Quad{triple = tr}))
		}
		return p.err
	case .TriG:
		p: trig.Parser
		trig.parser_init(&p, source, base)
		defer trig.parser_destroy(&p)
		for {
			q, ok := trig.parser_next(&p)
			if !ok {
				break
			}
			append(out, rdf.clone_quad(q))
		}
		return p.err
	}
	return {}
}

destroy_statements :: proc(qs: ^[dynamic]rdf.Quad) {
	for q in qs {
		rdf.destroy_quad(q)
	}
	delete(qs^)
}
