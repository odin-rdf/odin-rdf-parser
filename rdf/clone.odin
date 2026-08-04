package rdf

import "core:strings"

// clone deep-copies a borrowed value into owned memory, promoting it past
// the per-statement lifetime contract (ADR RDF-A-0001). Every string is
// copied; a triple term's pointed-to Triple is cloned recursively into a
// new allocation.
//
// destroy must be called with the same allocator to release the copy.
clone :: proc {
	clone_term,
	clone_triple,
	clone_quad,
	clone_graph_label,
}

// destroy releases a value produced by clone with the same allocator.
// Calling destroy on a borrowed (never-cloned) value, or with a different
// allocator than the clone used, is a programming error with undefined
// behavior — ownership is a documented contract, not tracked in the type.
destroy :: proc {
	destroy_term,
	destroy_triple,
	destroy_quad,
	destroy_graph_label,
}

clone_term :: proc(term: Term, allocator := context.allocator) -> Term {
	switch v in term {
	case IRI:
		return IRI(strings.clone(string(v), allocator))
	case Blank_Node:
		return Blank_Node(strings.clone(string(v), allocator))
	case Literal:
		return Literal {
			lexical   = strings.clone(v.lexical, allocator),
			datatype  = IRI(strings.clone(string(v.datatype), allocator)),
			language  = strings.clone(v.language, allocator),
			direction = v.direction,
		}
	case ^Triple:
		node := new(Triple, allocator)
		node^ = clone_triple(v^, allocator)
		return node
	}
	return nil
}

clone_triple :: proc(t: Triple, allocator := context.allocator) -> Triple {
	return {
		subject   = clone_term(t.subject, allocator),
		predicate = clone_term(t.predicate, allocator),
		object    = clone_term(t.object, allocator),
	}
}

clone_quad :: proc(q: Quad, allocator := context.allocator) -> Quad {
	return {
		triple = clone_triple(q.triple, allocator),
		graph  = clone_graph_label(q.graph, allocator),
	}
}

clone_graph_label :: proc(g: Graph_Label, allocator := context.allocator) -> Graph_Label {
	switch v in g {
	case IRI:
		return IRI(strings.clone(string(v), allocator))
	case Blank_Node:
		return Blank_Node(strings.clone(string(v), allocator))
	}
	return nil
}

destroy_term :: proc(term: Term, allocator := context.allocator) {
	switch v in term {
	case IRI:
		delete(string(v), allocator)
	case Blank_Node:
		delete(string(v), allocator)
	case Literal:
		delete(v.lexical, allocator)
		delete(string(v.datatype), allocator)
		delete(v.language, allocator)
	case ^Triple:
		destroy_triple(v^, allocator)
		free(v, allocator)
	}
}

destroy_triple :: proc(t: Triple, allocator := context.allocator) {
	destroy_term(t.subject, allocator)
	destroy_term(t.predicate, allocator)
	destroy_term(t.object, allocator)
}

destroy_quad :: proc(q: Quad, allocator := context.allocator) {
	destroy_triple(q.triple, allocator)
	destroy_graph_label(q.graph, allocator)
}

destroy_graph_label :: proc(g: Graph_Label, allocator := context.allocator) {
	switch v in g {
	case IRI:
		delete(string(v), allocator)
	case Blank_Node:
		delete(string(v), allocator)
	}
}
