package rdf

import chash "core:hash"

// hash returns a structural, buffer-independent 64-bit hash consistent
// with equal: equal values hash identically regardless of which buffers
// their strings borrow from. The underlying function (currently FNV-1a)
// is an internal detail that may change — do not persist hash values.
hash :: proc {
	hash_term,
	hash_triple,
	hash_quad,
	hash_graph_label,
}

hash_term :: proc(term: Term) -> u64 {
	return hash_term_seeded(term, FNV64A_OFFSET_BASIS)
}

hash_triple :: proc(t: Triple) -> u64 {
	return hash_triple_seeded(t, FNV64A_OFFSET_BASIS)
}

hash_quad :: proc(q: Quad) -> u64 {
	h := hash_triple_seeded(q.triple, FNV64A_OFFSET_BASIS)
	return hash_graph_label_seeded(q.graph, h)
}

hash_graph_label :: proc(g: Graph_Label) -> u64 {
	return hash_graph_label_seeded(g, FNV64A_OFFSET_BASIS)
}

@(private)
FNV64A_OFFSET_BASIS: u64 : 0xcbf29ce484222325

// hash_bytes is the single place the hash function is chosen; swapping
// the implementation changes every hash consistently with no public API
// impact.
@(private)
hash_bytes :: proc(data: []byte, seed: u64) -> u64 {
	return chash.fnv64a(data, seed)
}

// hash_string mixes in the length before the bytes so adjacent string
// components cannot collide by shifting content across their boundary.
@(private)
hash_string :: proc(s: string, seed: u64) -> u64 {
	length := transmute([8]byte)u64(len(s))
	h := hash_bytes(length[:], seed)
	return hash_bytes(transmute([]byte)s, h)
}

@(private)
hash_tag :: proc(tag: u8, seed: u64) -> u64 {
	b := [1]byte{tag}
	return hash_bytes(b[:], seed)
}

@(private)
hash_term_seeded :: proc(term: Term, seed: u64) -> u64 {
	switch v in term {
	case IRI:
		return hash_string(string(v), hash_tag(1, seed))
	case Blank_Node:
		return hash_string(string(v), hash_tag(2, seed))
	case Literal:
		h := hash_tag(3, seed)
		h = hash_string(v.lexical, h)
		h = hash_string(string(v.datatype), h)
		h = hash_string(v.language, h)
		return hash_tag(u8(v.direction), h)
	case ^Triple:
		if v == nil {
			return hash_tag(0, seed)
		}
		return hash_triple_seeded(v^, hash_tag(4, seed))
	}
	return hash_tag(0, seed)
}

@(private)
hash_triple_seeded :: proc(t: Triple, seed: u64) -> u64 {
	h := hash_term_seeded(t.subject, seed)
	h = hash_term_seeded(t.predicate, h)
	return hash_term_seeded(t.object, h)
}

@(private)
hash_graph_label_seeded :: proc(g: Graph_Label, seed: u64) -> u64 {
	switch v in g {
	case IRI:
		return hash_string(string(v), hash_tag(1, seed))
	case Blank_Node:
		return hash_string(string(v), hash_tag(2, seed))
	}
	return hash_tag(0, seed)
}
