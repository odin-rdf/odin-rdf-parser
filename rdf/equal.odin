package rdf

// equal reports structural, buffer-independent equality: two values are
// equal iff they denote the same RDF term or statement, regardless of
// which buffers their strings borrow from. It differs from the built-in
// `==` only for RDF-star triple terms, which `==` compares by pointer
// identity and equal compares by structure (with a same-pointer fast
// path).
equal :: proc {
	equal_term,
	equal_triple,
	equal_quad,
	equal_graph_label,
}

equal_term :: proc(a, b: Term) -> bool {
	switch av in a {
	case IRI:
		bv, ok := b.(IRI)
		return ok && av == bv
	case Blank_Node:
		bv, ok := b.(Blank_Node)
		return ok && av == bv
	case Literal:
		bv, ok := b.(Literal)
		return ok && av == bv
	case ^Triple:
		bv, ok := b.(^Triple)
		if !ok {
			return false
		}
		if av == bv {
			return true
		}
		if av == nil || bv == nil {
			return false
		}
		return equal_triple(av^, bv^)
	}
	return a == nil && b == nil
}

equal_triple :: proc(a, b: Triple) -> bool {
	return equal_term(a.subject, b.subject) &&
		equal_term(a.predicate, b.predicate) &&
		equal_term(a.object, b.object)
}

equal_quad :: proc(a, b: Quad) -> bool {
	return equal_triple(a.triple, b.triple) && equal_graph_label(a.graph, b.graph)
}

equal_graph_label :: proc(a, b: Graph_Label) -> bool {
	switch av in a {
	case IRI:
		bv, ok := b.(IRI)
		return ok && av == bv
	case Blank_Node:
		bv, ok := b.(Blank_Node)
		return ok && av == bv
	}
	return a == nil && b == nil
}
