// Graph comparison for the W3C eval tests: statement multisets are
// equal up to a blank-node bijection. Expected results are unordered,
// so a deterministic first-occurrence label mapping is not sound — this
// is the full comparison, implemented as backtracking over statements
// grouped by a blank-node-masked skeleton key. Ground statements have
// unique skeletons, so only genuinely ambiguous blank-node statements
// ever branch; W3C eval graphs are small.
package w3c

import "core:strings"

import rdf "../../../rdf"

// graphs_isomorphic reports whether the two statement lists denote the
// same dataset up to a blank-node bijection (labels in graph position
// participate in the same bijection). RDF graphs are SETS: exact
// duplicate statements collapse before comparison — a document may
// assert the same triple twice (W3C annotation-07).
graphs_isomorphic :: proc(all_as, all_bs: []rdf.Quad) -> bool {
	as_list := dedupe(all_as)
	bs_list := dedupe(all_bs)
	defer delete(as_list)
	defer delete(bs_list)
	as, bs := as_list[:], bs_list[:]

	if len(as) != len(bs) {
		return false
	}
	if len(as) == 0 {
		return true
	}

	groups: map[string][dynamic]int
	defer {
		for key, idxs in groups {
			delete(key)
			delete(idxs)
		}
		delete(groups)
	}
	for q, j in bs {
		key := skeleton(q)
		if idxs, found := &groups[key]; found {
			append(idxs, j)
			delete(key)
		} else {
			lst: [dynamic]int
			append(&lst, j)
			groups[key] = lst
		}
	}

	used := make([]bool, len(bs))
	defer delete(used)
	fwd: map[string]string
	bwd: map[string]string
	trail: [dynamic]string
	defer delete(fwd)
	defer delete(bwd)
	defer delete(trail)

	return match_from(0, as, bs, &groups, used, &fwd, &bwd, &trail)
}

// dedupe drops statements whose exact serialization (labels included)
// was already seen.
@(private = "file")
dedupe :: proc(qs: []rdf.Quad) -> [dynamic]rdf.Quad {
	seen: map[string]bool
	defer {
		for key in seen {
			delete(key)
		}
		delete(seen)
	}
	out: [dynamic]rdf.Quad
	for q in qs {
		key := exact_key(q)
		if seen[key] {
			delete(key)
			continue
		}
		seen[key] = true
		append(&out, q)
	}
	return out
}

@(private = "file")
match_from :: proc(
	i: int,
	as, bs: []rdf.Quad,
	groups: ^map[string][dynamic]int,
	used: []bool,
	fwd, bwd: ^map[string]string,
	trail: ^[dynamic]string,
) -> bool {
	if i == len(as) {
		return true
	}
	key := skeleton(as[i])
	defer delete(key)
	idxs, found := groups[key]
	if !found {
		return false
	}
	for j in idxs {
		if used[j] {
			continue
		}
		mark := len(trail)
		if quad_match(as[i], bs[j], fwd, bwd, trail) {
			used[j] = true
			if match_from(i + 1, as, bs, groups, used, fwd, bwd, trail) {
				return true
			}
			used[j] = false
		}
		unwind(fwd, bwd, trail, mark)
	}
	return false
}

@(private = "file")
unwind :: proc(fwd, bwd: ^map[string]string, trail: ^[dynamic]string, mark: int) {
	for k in trail[mark:] {
		mapped := fwd[k]
		delete_key(fwd, k)
		delete_key(bwd, mapped)
	}
	resize(trail, mark)
}

@(private = "file")
quad_match :: proc(a, b: rdf.Quad, fwd, bwd: ^map[string]string, trail: ^[dynamic]string) -> bool {
	if !term_match(a.subject, b.subject, fwd, bwd, trail) {
		return false
	}
	if !term_match(a.predicate, b.predicate, fwd, bwd, trail) {
		return false
	}
	if !term_match(a.object, b.object, fwd, bwd, trail) {
		return false
	}
	switch ga in a.graph {
	case rdf.IRI:
		gb, is_iri := b.graph.(rdf.IRI)
		return is_iri && ga == gb
	case rdf.Blank_Node:
		gb, is_blank := b.graph.(rdf.Blank_Node)
		return is_blank && blank_match(ga, gb, fwd, bwd, trail)
	}
	return b.graph == nil
}

@(private = "file")
term_match :: proc(a, b: rdf.Term, fwd, bwd: ^map[string]string, trail: ^[dynamic]string) -> bool {
	#partial switch va in a {
	case rdf.Blank_Node:
		vb, is_blank := b.(rdf.Blank_Node)
		return is_blank && blank_match(va, vb, fwd, bwd, trail)
	case ^rdf.Triple:
		vb, is_tt := b.(^rdf.Triple)
		if !is_tt {
			return false
		}
		return term_match(va.subject, vb.subject, fwd, bwd, trail) &&
			term_match(va.predicate, vb.predicate, fwd, bwd, trail) &&
			term_match(va.object, vb.object, fwd, bwd, trail)
	}
	return rdf.equal_term(a, b)
}

@(private = "file")
blank_match :: proc(a, b: rdf.Blank_Node, fwd, bwd: ^map[string]string, trail: ^[dynamic]string) -> bool {
	la, lb := string(a), string(b)
	if mapped, has := fwd[la]; has {
		return mapped == lb
	}
	if _, taken := bwd[lb]; taken {
		return false
	}
	fwd[la] = lb
	bwd[lb] = la
	append(trail, la)
	return true
}

// skeleton is a structural key with blank nodes masked; statements can
// only match if their skeletons are equal (collisions merely widen the
// candidate set — quad_match re-verifies everything). exact_key keeps
// the labels, for set-dedupe.
@(private = "file")
skeleton :: proc(q: rdf.Quad) -> string {
	return serialize(q, false)
}

@(private = "file")
exact_key :: proc(q: rdf.Quad) -> string {
	return serialize(q, true)
}

@(private = "file")
serialize :: proc(q: rdf.Quad, with_labels: bool) -> string {
	sb := strings.builder_make()
	serialize_term(&sb, q.subject, with_labels)
	strings.write_byte(&sb, 0x1F)
	serialize_term(&sb, q.predicate, with_labels)
	strings.write_byte(&sb, 0x1F)
	serialize_term(&sb, q.object, with_labels)
	strings.write_byte(&sb, 0x1F)
	switch g in q.graph {
	case rdf.IRI:
		strings.write_byte(&sb, 'G')
		strings.write_string(&sb, string(g))
	case rdf.Blank_Node:
		strings.write_byte(&sb, '*')
		if with_labels {
			strings.write_string(&sb, string(g))
		}
	}
	return strings.to_string(sb)
}

@(private = "file")
serialize_term :: proc(sb: ^strings.Builder, term: rdf.Term, with_labels: bool) {
	switch v in term {
	case rdf.IRI:
		strings.write_byte(sb, 'I')
		strings.write_string(sb, string(v))
	case rdf.Blank_Node:
		strings.write_byte(sb, '*')
		if with_labels {
			strings.write_string(sb, string(v))
		}
	case rdf.Literal:
		strings.write_byte(sb, 'L')
		strings.write_string(sb, v.lexical)
		strings.write_byte(sb, 0x1E)
		strings.write_string(sb, string(v.datatype))
		strings.write_byte(sb, 0x1E)
		strings.write_string(sb, v.language)
		strings.write_byte(sb, byte(v.direction))
	case ^rdf.Triple:
		strings.write_byte(sb, '(')
		serialize_term(sb, v.subject, with_labels)
		strings.write_byte(sb, 0x1E)
		serialize_term(sb, v.predicate, with_labels)
		strings.write_byte(sb, 0x1E)
		serialize_term(sb, v.object, with_labels)
		strings.write_byte(sb, ')')
	}
}
