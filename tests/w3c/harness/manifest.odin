// Package w3c runs the vendored W3C conformance suites against the
// parsers. Manifests are parsed with the library's own Turtle parser —
// the harness that validates the parsers runs on one of them
// (RDF-T-0020, retiring the hand-rolled reader from RDF-T-0010).
//
// Circularity guard: a Turtle parser bug that silently dropped manifest
// entries could mask conformance failures, so run_suite asserts the
// exact entry count recorded for each suite when it first passed.
package w3c

import "core:strings"

import rdf "../../../rdf"
import turtle "../../../rdf/turtle"

// MANIFEST_BASE anchors the manifests' relative IRIs; entry and file
// identifiers are recovered by stripping it again.
MANIFEST_BASE :: "https://manifest.invalid/"

MF_NS :: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#"
MF_MANIFEST :: rdf.IRI(MF_NS + "Manifest")
MF_ENTRIES :: rdf.IRI(MF_NS + "entries")
MF_NAME :: rdf.IRI(MF_NS + "name")
MF_ACTION :: rdf.IRI(MF_NS + "action")
MF_RESULT :: rdf.IRI(MF_NS + "result")

Entry :: struct {
	id:       string, // entry IRI with the manifest base stripped
	name:     string, // mf:name
	type_str: string, // full rdf:type IRI, e.g. ...rdftest#TestTurtleEval
	action:   string, // input file name relative to the suite directory
	result:   string, // expected-output file for eval tests ("" otherwise)
}

destroy_entries :: proc(entries: ^[dynamic]Entry) {
	for e in entries {
		delete(e.id)
		delete(e.name)
		delete(e.type_str)
		delete(e.action)
		delete(e.result)
	}
	delete(entries^)
}

// parse_manifest reads a manifest.ttl with the real Turtle parser and
// walks the mf:entries collection, preserving the manifest's order.
// Returned entries own their strings; free with destroy_entries.
parse_manifest :: proc(source: string) -> [dynamic]Entry {
	statements: [dynamic]rdf.Triple
	defer {
		for t in statements {
			rdf.destroy_triple(t)
		}
		delete(statements)
	}

	p: turtle.Parser
	turtle.parser_init(&p, transmute([]byte)source, MANIFEST_BASE)
	defer turtle.parser_destroy(&p)
	for {
		t, ok := turtle.parser_next(&p)
		if !ok {
			break
		}
		append(&statements, rdf.clone_triple(t))
	}
	entries := make([dynamic]Entry)
	if p.err.kind != .None {
		// Callers assert on the entry count; an empty list fails loudly.
		return entries
	}

	// Index statements by subject for the walk below.
	by_subject: map[string][dynamic]int
	defer {
		for key, idxs in by_subject {
			delete(key)
			delete(idxs)
		}
		delete(by_subject)
	}
	for t, i in statements {
		key := subject_key(t.subject)
		if key == "" {
			continue
		}
		if idxs, found := &by_subject[key]; found {
			append(idxs, i)
			delete(key)
		} else {
			lst: [dynamic]int
			append(&lst, i)
			by_subject[key] = lst
		}
	}

	object_of :: proc(
		statements: []rdf.Triple,
		by_subject: ^map[string][dynamic]int,
		subject: rdf.Term,
		predicate: rdf.IRI,
	) -> rdf.Term {
		key := subject_key(subject)
		defer delete(key)
		idxs, found := by_subject[key]
		if !found {
			return nil
		}
		for i in idxs {
			if pred, is_iri := statements[i].predicate.(rdf.IRI); is_iri && pred == predicate {
				return statements[i].object
			}
		}
		return nil
	}

	// Find the manifest node and the head of its entry collection.
	manifest_subject: rdf.Term
	for t in statements {
		if pred, is_iri := t.predicate.(rdf.IRI); is_iri && pred == rdf.RDF_TYPE {
			if obj, obj_iri := t.object.(rdf.IRI); obj_iri && obj == MF_MANIFEST {
				manifest_subject = t.subject
				break
			}
		}
	}
	if manifest_subject == nil {
		return entries
	}

	cell := object_of(statements[:], &by_subject, manifest_subject, MF_ENTRIES)
	for cell != nil {
		if iri, is_iri := cell.(rdf.IRI); is_iri && iri == rdf.RDF_NIL {
			break
		}
		entry_node := object_of(statements[:], &by_subject, cell, rdf.RDF_FIRST)
		if entry_node == nil {
			break
		}

		e: Entry
		if id, is_iri := entry_node.(rdf.IRI); is_iri {
			e.id = strings.clone(strip_base(string(id)))
		}
		if type_term := object_of(statements[:], &by_subject, entry_node, rdf.RDF_TYPE); type_term != nil {
			if iri, is_iri := type_term.(rdf.IRI); is_iri {
				e.type_str = strings.clone(string(iri))
			}
		}
		if name_term := object_of(statements[:], &by_subject, entry_node, MF_NAME); name_term != nil {
			if lit, is_lit := name_term.(rdf.Literal); is_lit {
				e.name = strings.clone(lit.lexical)
			}
		}
		if action_term := object_of(statements[:], &by_subject, entry_node, MF_ACTION); action_term != nil {
			if iri, is_iri := action_term.(rdf.IRI); is_iri {
				e.action = strings.clone(strip_base(string(iri)))
			}
		}
		if result_term := object_of(statements[:], &by_subject, entry_node, MF_RESULT); result_term != nil {
			if iri, is_iri := result_term.(rdf.IRI); is_iri {
				e.result = strings.clone(strip_base(string(iri)))
			}
		}
		if e.action != "" {
			append(&entries, e)
		} else {
			delete(e.id)
			delete(e.name)
			delete(e.type_str)
			delete(e.result)
		}

		cell = object_of(statements[:], &by_subject, cell, rdf.RDF_REST)
	}
	return entries
}

@(private = "file")
subject_key :: proc(term: rdf.Term) -> string {
	#partial switch v in term {
	case rdf.IRI:
		return strings.concatenate({"I", string(v)})
	case rdf.Blank_Node:
		return strings.concatenate({"B", string(v)})
	}
	return ""
}

@(private = "file")
strip_base :: proc(iri: string) -> string {
	if strings.has_prefix(iri, MANIFEST_BASE) {
		return iri[len(MANIFEST_BASE):]
	}
	return iri
}
