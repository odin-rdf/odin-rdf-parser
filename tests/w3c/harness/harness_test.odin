package w3c

import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import scan "../../../rdf/internal/scanner"
import quads "../../../rdf/quads"
import triples "../../../rdf/triples"

SUITE_ROOT :: #directory + ".."

Format :: enum {
	N_Triples,
	N_Quads,
}

@(test)
test_w3c_rdf11_ntriples :: proc(t: ^testing.T) {
	run_suite(t, "rdf11-ntriples", .N_Triples)
}

@(test)
test_w3c_rdf11_nquads :: proc(t: ^testing.T) {
	run_suite(t, "rdf11-nquads", .N_Quads)
}

@(test)
test_w3c_rdf12_ntriples :: proc(t: ^testing.T) {
	run_suite(t, "rdf12-ntriples-syntax", .N_Triples)
}

@(test)
test_w3c_rdf12_nquads :: proc(t: ^testing.T) {
	run_suite(t, "rdf12-nquads-syntax", .N_Quads)
}

run_suite :: proc(t: ^testing.T, suite: string, format: Format) {
	manifest_path, _ := filepath.join({SUITE_ROOT, suite, "manifest.ttl"})
	defer delete(manifest_path)
	manifest_data, manifest_err := os.read_entire_file(manifest_path, context.allocator)
	if !testing.expectf(t, manifest_err == nil, "cannot read manifest %s: %v", manifest_path, manifest_err) {
		return
	}
	defer delete(manifest_data)

	entries := parse_manifest(string(manifest_data))
	defer delete(entries)
	testing.expectf(t, len(entries) > 0, "%s: no entries parsed from manifest", suite)

	passed := 0
	for e in entries {
		positive: bool
		switch {
		case strings.contains(e.type_str, "PositiveSyntax"):
			positive = true
		case strings.contains(e.type_str, "NegativeSyntax"):
			positive = false
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

		err := parse_document(content, format)
		delete(content)

		if positive {
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
		} else {
			if testing.expectf(t, err.kind != .None, "%s (%s): malformed document was accepted", e.id, e.name) {
				passed += 1
			}
		}
	}
	log.infof("%s: %d/%d conformance tests passed", suite, passed, len(entries))
}

parse_document :: proc(source: []byte, format: Format) -> scan.Error {
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
	}
	return {}
}
