package rdf

import "base:runtime"
import "core:strings"

// Intern_Table deduplicates strings: interning equal content repeatedly
// returns the same owned backing storage. Interned terms remain valid
// until intern_table_destroy — the intended way to keep many statements
// from a parse without cloning every repeated IRI.
Intern_Table :: struct {
	entries:   map[string]string, // key and value are the same owned string
	triples:   [dynamic]^Triple, // triple-term nodes owned by the table
	allocator: runtime.Allocator,
}

intern_table_init :: proc(t: ^Intern_Table, allocator := context.allocator) {
	t.allocator = allocator
	t.entries = make(map[string]string, 8, allocator)
	t.triples = make([dynamic]^Triple, 0, 8, allocator)
}

intern_table_destroy :: proc(t: ^Intern_Table) {
	for _, owned in t.entries {
		delete(owned, t.allocator)
	}
	delete(t.entries)
	for node in t.triples {
		free(node, t.allocator)
	}
	delete(t.triples)
	t^ = {}
}

// intern returns an owned string equal to s, allocating only the first
// time each distinct content is seen.
intern :: proc(t: ^Intern_Table, s: string) -> string {
	if existing, ok := t.entries[s]; ok {
		return existing
	}
	owned := strings.clone(s, t.allocator)
	t.entries[owned] = owned
	return owned
}

// intern_term returns a term whose strings live in the table; for triple
// terms the pointed-to Triple is re-allocated and owned by the table.
intern_term :: proc(t: ^Intern_Table, term: Term) -> Term {
	switch v in term {
	case IRI:
		return IRI(intern(t, string(v)))
	case Blank_Node:
		return Blank_Node(intern(t, string(v)))
	case Literal:
		return Literal {
			lexical   = intern(t, v.lexical),
			datatype  = IRI(intern(t, string(v.datatype))),
			language  = intern(t, v.language),
			direction = v.direction,
		}
	case ^Triple:
		node := new(Triple, t.allocator)
		node^ = intern_triple(t, v^)
		append(&t.triples, node)
		return node
	}
	return nil
}

intern_triple :: proc(t: ^Intern_Table, tr: Triple) -> Triple {
	return {
		subject   = intern_term(t, tr.subject),
		predicate = intern_term(t, tr.predicate),
		object    = intern_term(t, tr.object),
	}
}

intern_quad :: proc(t: ^Intern_Table, q: Quad) -> Quad {
	result := Quad {
		triple = intern_triple(t, q.triple),
	}
	switch v in q.graph {
	case IRI:
		result.graph = IRI(intern(t, string(v)))
	case Blank_Node:
		result.graph = Blank_Node(intern(t, string(v)))
	}
	return result
}
