// Turtle-family parser core: directives, term construction, and the
// statement queue. rdf/turtle (and later rdf/trig) are thin public
// layers over this, the same way the line-based formats layer over
// rdf/internal/statement.
//
// Memory contract (ADR RDF-A-0001, RDF-I-0003 design):
//
//   - The intern table owns every prefix expansion, resolved IRI, and
//     synthesized or remapped blank-node label for the parser's
//     LIFETIME — those strings stay valid until destroy.
//   - Copy-on-write unescapes of string literals and document
//     blank-node labels are borrowed/owned per STATEMENT — valid only
//     until the statement's last triple has been pulled.
//   - The statement queue is reset (not freed) per top-level statement;
//     steady-state parsing allocates only for IRIs the intern table has
//     not seen.
package ttl

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

import rdf "../.."
import resolve_pkg "../iri"

Parser :: struct {
	scanner:       Scanner,
	allocator:     runtime.Allocator,
	intern:        rdf.Intern_Table, // parser-lifetime strings (see package doc)
	prefixes:      map[string]string, // prefix -> namespace IRI, both interned
	base:          string, // interned; "" until a base is established
	iri_scratch:   resolve_pkg.Scratch,
	name_scratch:  [dynamic]byte, // pname expansion, IRI unescape, label synthesis
	owned:         [dynamic]string, // per-statement CoW unescapes
	nodes:         [dynamic]^rdf.Triple, // per-statement triple-term nodes
	queue:         [dynamic]rdf.Triple, // fan-out of the current statement
	queue_head:    int,
	lookahead:     Token,
	has_lookahead: bool,
	anon_counter:  int,
	depth:         int, // current [ ] / ( ) / << >> nesting
	err:           Error,
	// TriG state. trig_mode enables graph blocks and the GRAPH keyword;
	// current_graph is the graph label of the most recently parsed
	// statement (nil = default graph) — constant while its queue drains,
	// which is how the trig layer attaches graphs to yielded triples.
	trig_mode:     bool,
	in_graph:      bool,
	current_graph: rdf.Graph_Label,
}

// MAX_NESTING_DEPTH bounds recursive structures so pathological input
// produces a structured error instead of a stack overflow.
MAX_NESTING_DEPTH :: 128

init :: proc(p: ^Parser, source: []byte, base: string, allocator: runtime.Allocator) {
	p^ = {}
	scanner_init(&p.scanner, source)
	p.allocator = allocator
	rdf.intern_table_init(&p.intern, allocator)
	p.prefixes = make(map[string]string, 8, allocator)
	p.iri_scratch.merged.allocator = allocator
	p.iri_scratch.out.allocator = allocator
	p.name_scratch.allocator = allocator
	p.owned.allocator = allocator
	p.nodes.allocator = allocator
	p.queue.allocator = allocator
	if base != "" {
		resolved, ok := resolve_pkg.resolve(&p.intern, "", base, &p.iri_scratch)
		if !ok {
			// A relative initial base can never resolve anything.
			p.err = Error{kind = .Relative_IRI, line = 1, column = 1}
			return
		}
		p.base = resolved
	}
}

destroy :: proc(p: ^Parser) {
	free_statement(p)
	delete(p.owned)
	delete(p.nodes)
	delete(p.queue)
	delete(p.prefixes)
	delete(p.name_scratch)
	resolve_pkg.scratch_destroy(&p.iri_scratch)
	rdf.intern_table_destroy(&p.intern)
	p^ = {}
}

// free_statement releases the previous statement's CoW allocations and
// triple-term nodes — the per-statement validity contract.
free_statement :: proc(p: ^Parser) {
	for s in p.owned {
		delete(s, p.allocator)
	}
	clear(&p.owned)
	for node in p.nodes {
		free(node, p.allocator)
	}
	clear(&p.nodes)
}

// next_triple yields the next triple: from the current statement's queue
// if one is pending, otherwise by parsing directives until the next
// triples statement. ok is false at end of input or on error; err.kind
// distinguishes (.None means clean end). Errors are sticky.
next_triple :: proc(p: ^Parser) -> (t: rdf.Triple, ok: bool) {
	if p.err.kind != .None {
		return {}, false
	}
	if p.queue_head < len(p.queue) {
		t = p.queue[p.queue_head]
		p.queue_head += 1
		return t, true
	}

	free_statement(p)
	clear(&p.queue) // reset, capacity retained
	p.queue_head = 0

	for {
		p.depth = 0
		tok, tok_ok := next_token(p)
		if !tok_ok {
			if !scanner_failed(p) && p.in_graph {
				fail_here(p, .Unclosed_Graph)
			}
			return {}, false
		}

		if p.in_graph {
			if tok.kind == .R_Brace {
				p.in_graph = false
				p.current_graph = nil
				continue
			}
			if !parse_triples(p, tok) {
				return {}, false
			}
			t = p.queue[p.queue_head]
			p.queue_head += 1
			return t, true
		}

		#partial switch tok.kind {
		case .At_Prefix:
			if !parse_prefix_directive(p, true) {
				return {}, false
			}
			continue
		case .Sparql_Prefix:
			if !parse_prefix_directive(p, false) {
				return {}, false
			}
			continue
		case .At_Base:
			if !parse_base_directive(p, true) {
				return {}, false
			}
			continue
		case .Sparql_Base:
			if !parse_base_directive(p, false) {
				return {}, false
			}
			continue
		case .At_Version:
			if !parse_version_directive(p, true) {
				return {}, false
			}
			continue
		case .Sparql_Version:
			if !parse_version_directive(p, false) {
				return {}, false
			}
			continue
		}

		if p.trig_mode {
			entered, parsed, block_ok := parse_block_start(p, tok)
			if !block_ok {
				return {}, false
			}
			if entered {
				continue
			}
			if parsed {
				t = p.queue[p.queue_head]
				p.queue_head += 1
				return t, true
			}
		}

		if !parse_triples(p, tok) {
			return {}, false
		}
		t = p.queue[p.queue_head]
		p.queue_head += 1
		return t, true
	}
}

// parse_block_start handles the TriG top-level forms whose first token
// is ambiguous with plain triples: '{ … }', 'GRAPH label { … }',
// 'label { … }', and '[] { … }'. entered reports a graph block was
// opened; parsed reports the label turned out to be a subject and its
// whole statement was parsed into the queue. Both false (with ok) means
// the token was not consumed and the caller parses plain triples.
@(private)
parse_block_start :: proc(p: ^Parser, tok: Token) -> (entered: bool, parsed: bool, ok: bool) {
	#partial switch tok.kind {
	case .L_Brace:
		p.in_graph = true
		p.current_graph = nil
		return true, false, true

	case .Graph_Keyword:
		label, lok := parse_graph_label(p)
		if !lok {
			return false, false, false
		}
		open, ook := next_token(p)
		if !ook {
			if !scanner_failed(p) {
				fail_here(p, .Expected_Graph_Block)
			}
			return false, false, false
		}
		if open.kind != .L_Brace {
			fail_at(p, .Expected_Graph_Block, open)
			return false, false, false
		}
		p.in_graph = true
		p.current_graph = label
		return true, false, true

	case .IRI_Ref, .PName, .Blank_Node_Label:
		// 'labelOrSubject (wrappedGraph | predicateObjectList '.')' —
		// parse the term, then a '{' decides.
		subject, sok := parse_subject(p, tok)
		if !sok {
			return false, false, false
		}
		if peeked, has := peek_token(p); has && peeked.kind == .L_Brace {
			_, _ = next_token(p)
			p.in_graph = true
			p.current_graph = term_to_graph_label(subject)
			return true, false, true
		} else if !has && scanner_failed(p) {
			return false, false, false
		}
		if !parse_predicate_object_list(p, subject) {
			return false, false, false
		}
		if !expect_statement_end(p) {
			return false, false, false
		}
		return false, true, true

	case .L_Bracket:
		// A bare ANON can also be a graph label ('[] { … }') — a
		// blankNodePropertyList requires a non-empty list, so only the
		// empty form is ambiguous.
		subject, has_props, bok := parse_bnode_property_list(p, tok)
		if !bok {
			return false, false, false
		}
		if !has_props {
			if peeked, has := peek_token(p); has && peeked.kind == .L_Brace {
				_, _ = next_token(p)
				p.in_graph = true
				p.current_graph = subject.(rdf.Blank_Node)
				return true, false, true
			} else if !has && scanner_failed(p) {
				return false, false, false
			}
		}
		if has_props {
			peeked, has := peek_token(p)
			if !has && scanner_failed(p) {
				return false, false, false
			}
			if has && peeked.kind == .Dot {
				return false, true, expect_statement_end(p)
			}
		}
		if !parse_predicate_object_list(p, subject) {
			return false, false, false
		}
		return false, true, expect_statement_end(p)
	}
	return false, false, true
}

@(private)
parse_graph_label :: proc(p: ^Parser) -> (label: rdf.Graph_Label, ok: bool) {
	tok, tok_ok := next_token(p)
	if !tok_ok {
		if !scanner_failed(p) {
			fail_here(p, .Invalid_Graph_Label)
		}
		return nil, false
	}
	#partial switch tok.kind {
	case .IRI_Ref:
		term, iok := iri_ref_term(p, tok)
		if !iok {
			return nil, false
		}
		return term.(rdf.IRI), true
	case .PName:
		term, pok := pname_term(p, tok)
		if !pok {
			return nil, false
		}
		return term.(rdf.IRI), true
	case .Blank_Node_Label:
		return doc_blank_node(p, tok).(rdf.Blank_Node), true
	case .L_Bracket:
		term, aok := parse_anon(p, tok)
		if !aok {
			return nil, false
		}
		return term.(rdf.Blank_Node), true
	}
	fail_at(p, .Invalid_Graph_Label, tok)
	return nil, false
}

@(private)
term_to_graph_label :: proc(term: rdf.Term) -> rdf.Graph_Label {
	#partial switch v in term {
	case rdf.IRI:
		return v
	case rdf.Blank_Node:
		return v
	}
	return nil
}

// parse_prefix_directive handles '@prefix p: <iri> .' and the SPARQL
// form 'PREFIX p: <iri>' (no dot). A later declaration of the same
// prefix overrides the earlier one, per spec.
@(private)
parse_prefix_directive :: proc(p: ^Parser, at_form: bool) -> bool {
	tok, ok := next_token(p)
	if !ok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Prefix_Name)
		}
		return false
	}
	colon := strings.index_byte(tok.text, ':')
	if tok.kind != .PName || colon != len(tok.text) - 1 {
		fail_at(p, .Expected_Prefix_Name, tok)
		return false
	}
	prefix := tok.text[:colon]

	iri_tok, iok := next_token(p)
	if !iok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_IRI)
		}
		return false
	}
	if iri_tok.kind != .IRI_Ref {
		fail_at(p, .Expected_IRI, iri_tok)
		return false
	}
	ns, nok := resolve_iri_token(p, iri_tok)
	if !nok {
		return false
	}
	p.prefixes[rdf.intern(&p.intern, prefix)] = string(ns)
	if at_form {
		return expect_dot(p)
	}
	return true
}

// parse_base_directive handles '@base <iri> .' and 'BASE <iri>'. A
// relative IRI resolves against the base in effect at this point.
@(private)
parse_base_directive :: proc(p: ^Parser, at_form: bool) -> bool {
	tok, ok := next_token(p)
	if !ok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_IRI)
		}
		return false
	}
	if tok.kind != .IRI_Ref {
		fail_at(p, .Expected_IRI, tok)
		return false
	}
	base, bok := resolve_iri_token(p, tok)
	if !bok {
		return false
	}
	p.base = string(base)
	if at_form {
		return expect_dot(p)
	}
	return true
}

// parse_version_directive handles '@version "1.2" .' and the SPARQL
// form 'VERSION "1.2"' (RDF 1.2). The specifier must be a short quoted
// string; the value carries no semantics and is discarded.
@(private)
parse_version_directive :: proc(p: ^Parser, at_form: bool) -> bool {
	tok, ok := next_token(p)
	if !ok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Version_String)
		}
		return false
	}
	if tok.kind != .String_Literal || tok.long_string {
		fail_at(p, .Expected_Version_String, tok)
		return false
	}
	if at_form {
		return expect_dot(p)
	}
	return true
}

// parse_triples parses one triples statement whose first token has been
// consumed, appending its fan-out to the queue in document order (a
// nested structure's triples precede the triple that references it).
@(private)
parse_triples :: proc(p: ^Parser, first: Token) -> bool {
	p.depth = 0
	subject: rdf.Term
	sok: bool
	pol_optional := false
	#partial switch first.kind {
	case .L_Bracket:
		has_props: bool
		subject, has_props, sok = parse_bnode_property_list(p, first)
		// 'triples ::= … | blankNodePropertyList predicateObjectList?':
		// only a non-empty property list may stand alone; a bare ANON
		// subject still needs predicates.
		pol_optional = has_props
	case .L_Paren:
		subject, sok = parse_collection(p, first)
	case .Reified_Open:
		// 'reifiedTriple predicateObjectList?': the reified triple's own
		// rdf:reifies assertion makes it a complete statement.
		subject, sok = parse_reified_triple(p, first)
		pol_optional = true
	case:
		subject, sok = parse_subject(p, first)
	}
	if !sok {
		return false
	}
	if pol_optional {
		peeked, has := peek_token(p)
		if !has && scanner_failed(p) {
			return false
		}
		if has && (peeked.kind == .Dot || (p.in_graph && peeked.kind == .R_Brace)) {
			return expect_statement_end(p)
		}
	}
	if !parse_predicate_object_list(p, subject) {
		return false
	}
	return expect_statement_end(p)
}

// expect_statement_end consumes the statement terminator: a '.', or —
// inside a TriG graph block, where the final dot is optional
// ('triplesBlock ::= triples ('.' triplesBlock?)?') — a '}' left for
// the block loop to consume.
@(private)
expect_statement_end :: proc(p: ^Parser) -> bool {
	if p.in_graph {
		peeked, has := peek_token(p)
		if !has {
			if scanner_failed(p) {
				return false
			}
			fail_here(p, .Unclosed_Graph)
			return false
		}
		if peeked.kind == .R_Brace {
			return true
		}
	}
	return expect_dot(p)
}

@(private)
parse_subject :: proc(p: ^Parser, tok: Token) -> (term: rdf.Term, ok: bool) {
	#partial switch tok.kind {
	case .IRI_Ref:
		return iri_ref_term(p, tok)
	case .PName:
		return pname_term(p, tok)
	case .Blank_Node_Label:
		return doc_blank_node(p, tok), true
	}
	fail_at(p, .Expected_Subject, tok)
	return nil, false
}

// parse_predicate_object_list parses
// 'verb objectList (';' (verb objectList)?)*' — semicolon runs and a
// trailing semicolon are tolerated per the grammar.
@(private)
parse_predicate_object_list :: proc(p: ^Parser, subject: rdf.Term) -> bool {
	for {
		verb, vok := parse_verb(p)
		if !vok {
			return false
		}
		if !parse_object_list(p, subject, verb) {
			return false
		}
		saw_semicolon := false
		for {
			peeked, has := peek_token(p)
			if !has {
				if scanner_failed(p) {
					return false
				}
				return true // EOF; the caller's Dot check reports it
			}
			if peeked.kind != .Semicolon {
				break
			}
			_, _ = next_token(p)
			saw_semicolon = true
		}
		if !saw_semicolon {
			return true
		}
		// After ';' only a verb continues the list; anything else (the
		// '.'/']' terminator) means the semicolon was trailing.
		peeked, has := peek_token(p)
		if !has {
			return !scanner_failed(p)
		}
		#partial switch peeked.kind {
		case .A, .IRI_Ref, .PName:
		// next verb
		case:
			return true
		}
	}
}

// parse_object_list parses 'object annotation (',' object annotation)*'
// where annotation is the RDF 1.2 '(reifier | annotationBlock)*'.
@(private)
parse_object_list :: proc(p: ^Parser, subject: rdf.Term, verb: rdf.Term) -> bool {
	for {
		object, ook := parse_object(p)
		if !ook {
			return false
		}
		append(&p.queue, rdf.Triple{subject = subject, predicate = verb, object = object})
		if !parse_annotation(p, subject, verb, object) {
			return false
		}
		peeked, has := peek_token(p)
		if !has {
			return !scanner_failed(p) // EOF; the Dot check reports it
		}
		if peeked.kind != .Comma {
			return true
		}
		_, _ = next_token(p)
	}
}

// parse_annotation handles the RDF 1.2 annotation trailer after an
// object: '(reifier | annotationBlock)*'.
//
//   - '~ R?' asserts 'R rdf:reifies <<( s p o )>>' (fresh blank node
//     when R is omitted) and makes R the pending reifier.
//   - '{| pol |}' applies pol to the pending reifier — or, with none
//     pending, to a fresh blank node that first gets its own
//     rdf:reifies assertion. A block consumes the pending reifier, so
//     consecutive bare blocks each reify independently.
//
// One triple-term node is shared by every assertion about this object.
@(private)
parse_annotation :: proc(p: ^Parser, subject: rdf.Term, verb: rdf.Term, object: rdf.Term) -> bool {
	tt: rdf.Term // built lazily on the first use
	pending: rdf.Term
	for {
		peeked, has := peek_token(p)
		if !has {
			return !scanner_failed(p)
		}
		#partial switch peeked.kind {
		case .Tilde:
			_, _ = next_token(p)
			reifier, rok := parse_optional_reifier_target(p)
			if !rok {
				return false
			}
			if tt == nil {
				tt = triple_term_node(p, subject, verb, object)
			}
			append(&p.queue, rdf.Triple{subject = reifier, predicate = rdf.RDF_REIFIES, object = tt})
			pending = reifier
		case .Annotation_Open:
			open, _ := next_token(p)
			if !enter_nested(p, open) {
				return false
			}
			target := pending
			if target == nil {
				target = fresh_blank_node(p)
				if tt == nil {
					tt = triple_term_node(p, subject, verb, object)
				}
				append(&p.queue, rdf.Triple{subject = target, predicate = rdf.RDF_REIFIES, object = tt})
			}
			pending = nil
			if !parse_predicate_object_list(p, target) {
				return false
			}
			close, cok := next_token(p)
			if !cok {
				if !scanner_failed(p) {
					fail_here(p, .Unclosed_Annotation)
				}
				return false
			}
			if close.kind != .Annotation_Close {
				fail_at(p, .Unclosed_Annotation, close)
				return false
			}
			p.depth -= 1
		case:
			return true
		}
	}
}

// parse_optional_reifier_target parses the optional target of '~':
// an IRI, a blank node label, or ANON; a bare '~' synthesizes one.
@(private)
parse_optional_reifier_target :: proc(p: ^Parser) -> (term: rdf.Term, ok: bool) {
	peeked, has := peek_token(p)
	if !has {
		if scanner_failed(p) {
			return nil, false
		}
		return fresh_blank_node(p), true
	}
	#partial switch peeked.kind {
	case .IRI_Ref:
		_, _ = next_token(p)
		return iri_ref_term(p, peeked)
	case .PName:
		_, _ = next_token(p)
		return pname_term(p, peeked)
	case .Blank_Node_Label:
		_, _ = next_token(p)
		return doc_blank_node(p, peeked), true
	case .L_Bracket:
		open, _ := next_token(p)
		return parse_anon(p, open)
	}
	return fresh_blank_node(p), true
}

// parse_anon expects the ']' of a bare ANON '[ ]' — property lists are
// not permitted in this position.
@(private)
parse_anon :: proc(p: ^Parser, open: Token) -> (term: rdf.Term, ok: bool) {
	close, cok := next_token(p)
	if !cok {
		if !scanner_failed(p) {
			fail_here(p, .Unclosed_Property_List)
		}
		return nil, false
	}
	if close.kind != .R_Bracket {
		fail_at(p, .Unclosed_Property_List, close)
		return nil, false
	}
	return fresh_blank_node(p), true
}

// parse_reified_triple parses '<< rtSubject verb rtObject reifier? >>'
// from its consumed '<<' token. It asserts 'R rdf:reifies <<( s p o )>>'
// and denotes R (explicit, or a fresh blank node).
@(private)
parse_reified_triple :: proc(p: ^Parser, open: Token) -> (term: rdf.Term, ok: bool) {
	if !enter_nested(p, open) {
		return nil, false
	}
	defer p.depth -= 1

	stok, sok := next_token(p)
	if !sok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Subject)
		}
		return nil, false
	}
	subject: rdf.Term
	subject_ok: bool
	#partial switch stok.kind {
	case .IRI_Ref:
		subject, subject_ok = iri_ref_term(p, stok)
	case .PName:
		subject, subject_ok = pname_term(p, stok)
	case .Blank_Node_Label:
		subject, subject_ok = doc_blank_node(p, stok), true
	case .L_Bracket:
		subject, subject_ok = parse_anon(p, stok)
	case .Reified_Open:
		subject, subject_ok = parse_reified_triple(p, stok)
	case:
		fail_at(p, .Expected_Subject, stok)
		return nil, false
	}
	if !subject_ok {
		return nil, false
	}

	verb, vok := parse_verb(p)
	if !vok {
		return nil, false
	}

	otok, ook := next_token(p)
	if !ook {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Object)
		}
		return nil, false
	}
	object: rdf.Term
	object_ok: bool
	#partial switch otok.kind {
	case .IRI_Ref:
		object, object_ok = iri_ref_term(p, otok)
	case .PName:
		object, object_ok = pname_term(p, otok)
	case .Blank_Node_Label:
		object, object_ok = doc_blank_node(p, otok), true
	case .L_Bracket:
		object, object_ok = parse_anon(p, otok)
	case .String_Literal:
		object, object_ok = parse_literal(p, otok)
	case .Integer:
		object, object_ok = rdf.literal_typed(otok.text, rdf.XSD_INTEGER), true
	case .Decimal:
		object, object_ok = rdf.literal_typed(otok.text, rdf.XSD_DECIMAL), true
	case .Double:
		object, object_ok = rdf.literal_typed(otok.text, rdf.XSD_DOUBLE), true
	case .Boolean:
		object, object_ok = rdf.literal_typed(otok.text, rdf.XSD_BOOLEAN), true
	case .Triple_Term_Open:
		object, object_ok = parse_triple_term(p, otok)
	case .Reified_Open:
		object, object_ok = parse_reified_triple(p, otok)
	case:
		fail_at(p, .Expected_Object, otok)
		return nil, false
	}
	if !object_ok {
		return nil, false
	}

	reifier: rdf.Term
	peeked, has := peek_token(p)
	if has && peeked.kind == .Tilde {
		_, _ = next_token(p)
		rok: bool
		reifier, rok = parse_optional_reifier_target(p)
		if !rok {
			return nil, false
		}
	} else if !has && scanner_failed(p) {
		return nil, false
	} else {
		reifier = fresh_blank_node(p)
	}

	close, cok := next_token(p)
	if !cok {
		if !scanner_failed(p) {
			fail_here(p, .Unclosed_Reified_Triple)
		}
		return nil, false
	}
	if close.kind != .Reified_Close {
		fail_at(p, .Unclosed_Reified_Triple, close)
		return nil, false
	}

	tt := triple_term_node(p, subject, verb, object)
	append(&p.queue, rdf.Triple{subject = reifier, predicate = rdf.RDF_REIFIES, object = tt})
	return reifier, true
}

// parse_triple_term parses '<<( ttSubject verb ttObject )>>' from its
// consumed '<<(' token, yielding a triple-term node.
@(private)
parse_triple_term :: proc(p: ^Parser, open: Token) -> (term: rdf.Term, ok: bool) {
	if !enter_nested(p, open) {
		return nil, false
	}
	defer p.depth -= 1

	stok, sok := next_token(p)
	if !sok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Subject)
		}
		return nil, false
	}
	subject: rdf.Term
	subject_ok: bool
	#partial switch stok.kind {
	case .IRI_Ref:
		subject, subject_ok = iri_ref_term(p, stok)
	case .PName:
		subject, subject_ok = pname_term(p, stok)
	case .Blank_Node_Label:
		subject, subject_ok = doc_blank_node(p, stok), true
	case .L_Bracket:
		subject, subject_ok = parse_anon(p, stok)
	case:
		fail_at(p, .Expected_Subject, stok)
		return nil, false
	}
	if !subject_ok {
		return nil, false
	}

	verb, vok := parse_verb(p)
	if !vok {
		return nil, false
	}

	otok, ook := next_token(p)
	if !ook {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Object)
		}
		return nil, false
	}
	object: rdf.Term
	object_ok: bool
	#partial switch otok.kind {
	case .IRI_Ref:
		object, object_ok = iri_ref_term(p, otok)
	case .PName:
		object, object_ok = pname_term(p, otok)
	case .Blank_Node_Label:
		object, object_ok = doc_blank_node(p, otok), true
	case .L_Bracket:
		object, object_ok = parse_anon(p, otok)
	case .String_Literal:
		object, object_ok = parse_literal(p, otok)
	case .Integer:
		object, object_ok = rdf.literal_typed(otok.text, rdf.XSD_INTEGER), true
	case .Decimal:
		object, object_ok = rdf.literal_typed(otok.text, rdf.XSD_DECIMAL), true
	case .Double:
		object, object_ok = rdf.literal_typed(otok.text, rdf.XSD_DOUBLE), true
	case .Boolean:
		object, object_ok = rdf.literal_typed(otok.text, rdf.XSD_BOOLEAN), true
	case .Triple_Term_Open:
		object, object_ok = parse_triple_term(p, otok)
	case:
		fail_at(p, .Expected_Object, otok)
		return nil, false
	}
	if !object_ok {
		return nil, false
	}

	close, cok := next_token(p)
	if !cok {
		if !scanner_failed(p) {
			fail_here(p, .Unclosed_Triple_Term)
		}
		return nil, false
	}
	if close.kind != .Triple_Term_Close {
		fail_at(p, .Unclosed_Triple_Term, close)
		return nil, false
	}
	return triple_term_node(p, subject, verb, object), true
}

// triple_term_node allocates a per-statement triple-term node (freed
// with free_statement, matching the line-based parsers).
@(private)
triple_term_node :: proc(p: ^Parser, subject: rdf.Term, verb: rdf.Term, object: rdf.Term) -> rdf.Term {
	node := new(rdf.Triple, p.allocator)
	node^ = {
		subject   = subject,
		predicate = verb,
		object    = object,
	}
	append(&p.nodes, node)
	return node
}

// parse_bnode_property_list parses '[ predicateObjectList? ]' from its
// consumed '[' token: a bare '[ ]' is ANON (a fresh node, no triples);
// otherwise the fresh node's triples are queued before the triple that
// will reference the node.
@(private)
parse_bnode_property_list :: proc(p: ^Parser, open: Token) -> (term: rdf.Term, has_props: bool, ok: bool) {
	if !enter_nested(p, open) {
		return nil, false, false
	}
	defer p.depth -= 1

	peeked, has := peek_token(p)
	if !has {
		if !scanner_failed(p) {
			fail_here(p, .Unclosed_Property_List)
		}
		return nil, false, false
	}
	node := fresh_blank_node(p)
	if peeked.kind == .R_Bracket {
		_, _ = next_token(p)
		return node, false, true
	}
	if !parse_predicate_object_list(p, node) {
		return nil, false, false
	}
	close, cok := next_token(p)
	if !cok {
		if !scanner_failed(p) {
			fail_here(p, .Unclosed_Property_List)
		}
		return nil, false, false
	}
	if close.kind != .R_Bracket {
		fail_at(p, .Unclosed_Property_List, close)
		return nil, false, false
	}
	return node, true, true
}

// parse_collection parses '( object* )' from its consumed '(' token
// into an rdf:first/rdf:rest chain; '()' is the term rdf:nil with no
// triples.
@(private)
parse_collection :: proc(p: ^Parser, open: Token) -> (term: rdf.Term, ok: bool) {
	if !enter_nested(p, open) {
		return nil, false
	}
	defer p.depth -= 1

	head: rdf.Term
	tail: rdf.Term // the chain's last cell, nil until the first element
	for {
		peeked, has := peek_token(p)
		if !has {
			if !scanner_failed(p) {
				fail_here(p, .Unclosed_Collection)
			}
			return nil, false
		}
		if peeked.kind == .R_Paren {
			_, _ = next_token(p)
			if tail == nil {
				return rdf.RDF_NIL, true
			}
			append(&p.queue, rdf.Triple{subject = tail, predicate = rdf.RDF_REST, object = rdf.RDF_NIL})
			return head, true
		}
		element, eok := parse_object(p)
		if !eok {
			return nil, false
		}
		cell := fresh_blank_node(p)
		if tail == nil {
			head = cell
		} else {
			append(&p.queue, rdf.Triple{subject = tail, predicate = rdf.RDF_REST, object = cell})
		}
		append(&p.queue, rdf.Triple{subject = cell, predicate = rdf.RDF_FIRST, object = element})
		tail = cell
	}
}

@(private)
enter_nested :: proc(p: ^Parser, tok: Token) -> bool {
	p.depth += 1
	if p.depth > MAX_NESTING_DEPTH {
		fail_at(p, .Nesting_Too_Deep, tok)
		return false
	}
	return true
}

@(private)
parse_verb :: proc(p: ^Parser) -> (term: rdf.Term, ok: bool) {
	tok, tok_ok := next_token(p)
	if !tok_ok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Predicate)
		}
		return nil, false
	}
	#partial switch tok.kind {
	case .A:
		return rdf.RDF_TYPE, true
	case .IRI_Ref:
		return iri_ref_term(p, tok)
	case .PName:
		return pname_term(p, tok)
	}
	fail_at(p, .Expected_Predicate, tok)
	return nil, false
}

@(private)
parse_object :: proc(p: ^Parser) -> (term: rdf.Term, ok: bool) {
	tok, tok_ok := next_token(p)
	if !tok_ok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Object)
		}
		return nil, false
	}
	#partial switch tok.kind {
	case .IRI_Ref:
		return iri_ref_term(p, tok)
	case .PName:
		return pname_term(p, tok)
	case .Blank_Node_Label:
		return doc_blank_node(p, tok), true
	case .String_Literal:
		return parse_literal(p, tok)
	case .Integer:
		return rdf.literal_typed(tok.text, rdf.XSD_INTEGER), true
	case .Decimal:
		return rdf.literal_typed(tok.text, rdf.XSD_DECIMAL), true
	case .Double:
		return rdf.literal_typed(tok.text, rdf.XSD_DOUBLE), true
	case .Boolean:
		return rdf.literal_typed(tok.text, rdf.XSD_BOOLEAN), true
	case .L_Bracket:
		term_, _, ok_ := parse_bnode_property_list(p, tok)
		return term_, ok_
	case .L_Paren:
		return parse_collection(p, tok)
	case .Reified_Open:
		return parse_reified_triple(p, tok)
	case .Triple_Term_Open:
		return parse_triple_term(p, tok)
	}
	fail_at(p, .Expected_Object, tok)
	return nil, false
}

@(private)
parse_literal :: proc(p: ^Parser, tok: Token) -> (term: rdf.Term, ok: bool) {
	lexical := cow_unescape(p, tok)
	peeked, has := peek_token(p)
	if !has {
		if scanner_failed(p) {
			return nil, false
		}
		return rdf.literal_plain(lexical), true // EOF; the Dot check reports it
	}
	#partial switch peeked.kind {
	case .Lang_Tag:
		_, _ = next_token(p)
		lang := peeked.text
		direction := rdf.Direction.None
		if idx := strings.index(lang, "--"); idx >= 0 {
			switch lang[idx + 2:] {
			case "ltr":
				direction = .LTR
			case "rtl":
				direction = .RTL
			case:
				fail_at(p, .Invalid_Direction, peeked)
				return nil, false
			}
			lang = lang[:idx]
		}
		if direction == .None {
			return rdf.literal_lang(lexical, lang), true
		}
		return rdf.literal_dir_lang(lexical, lang, direction), true
	case .Datatype_Marker:
		_, _ = next_token(p)
		dtok, dok := next_token(p)
		if !dok {
			if !scanner_failed(p) {
				fail_here(p, .Expected_Datatype)
			}
			return nil, false
		}
		dt_term: rdf.Term
		dt_ok: bool
		#partial switch dtok.kind {
		case .IRI_Ref:
			dt_term, dt_ok = iri_ref_term(p, dtok)
		case .PName:
			dt_term, dt_ok = pname_term(p, dtok)
		case:
			fail_at(p, .Expected_Datatype, dtok)
			return nil, false
		}
		if !dt_ok {
			return nil, false
		}
		dt := dt_term.(rdf.IRI)
		// RDF 1.2 reserves these datatypes for language-tag syntax.
		if dt == rdf.RDF_LANG_STRING || dt == rdf.RDF_DIR_LANG_STRING {
			fail_at(p, .Reserved_Datatype, dtok)
			return nil, false
		}
		return rdf.Literal{lexical = lexical, datatype = dt}, true
	}
	return rdf.literal_plain(lexical), true
}

@(private)
expect_dot :: proc(p: ^Parser) -> bool {
	tok, tok_ok := next_token(p)
	if !tok_ok {
		if !scanner_failed(p) {
			fail_here(p, .Expected_Dot)
		}
		return false
	}
	if tok.kind != .Dot {
		fail_at(p, .Expected_Dot, tok)
		return false
	}
	return true
}

// iri_ref_term builds a term from an IRIREF token: UCHAR-unescaped
// (into scratch — the resolver copies), resolved against the current
// base, interned.
@(private)
iri_ref_term :: proc(p: ^Parser, tok: Token) -> (term: rdf.Term, ok: bool) {
	text := tok.text
	if tok.has_escape {
		clear(&p.name_scratch)
		decode_escapes(&p.name_scratch, text)
		text = string(p.name_scratch[:])
	}
	resolved, rok := resolve_pkg.resolve(&p.intern, p.base, text, &p.iri_scratch)
	if !rok {
		fail_at(p, .Relative_IRI, tok)
		return nil, false
	}
	return rdf.IRI(resolved), true
}

// pname_term expands a prefixed name: namespace + backslash-stripped
// local part, interned. Expansion is pure concatenation — the result is
// NOT re-resolved against the base, per spec.
@(private)
pname_term :: proc(p: ^Parser, tok: Token) -> (term: rdf.Term, ok: bool) {
	colon := strings.index_byte(tok.text, ':')
	local := tok.text[colon + 1:]
	ns, found := p.prefixes[tok.text[:colon]]
	if !found {
		fail_at(p, .Undefined_Prefix, tok)
		return nil, false
	}
	clear(&p.name_scratch)
	append(&p.name_scratch, ns)
	if tok.has_escape {
		// PN_LOCAL_ESC: drop the backslash, keep the character. Percent
		// encodings are content and were never flagged as escapes.
		i := 0
		for i < len(local) {
			c := local[i]
			if c == '\\' {
				i += 1
				c = local[i]
			}
			append(&p.name_scratch, c)
			i += 1
		}
	} else {
		append(&p.name_scratch, local)
	}
	return rdf.IRI(rdf.intern(&p.intern, string(p.name_scratch[:]))), true
}

// doc_blank_node returns a document blank-node label, remapped out of
// the synthesized-label namespace when needed: labels matching
// ^B*b[0-9]+$ get one 'B' prepended (injective, streaming-safe), so a
// fresh_blank_node label can never collide with a document label.
@(private)
doc_blank_node :: proc(p: ^Parser, tok: Token) -> rdf.Term {
	label := tok.text
	if in_synthesized_namespace(label) {
		clear(&p.name_scratch)
		append(&p.name_scratch, 'B')
		append(&p.name_scratch, label)
		label = rdf.intern(&p.intern, string(p.name_scratch[:]))
	}
	return rdf.Blank_Node(label)
}

// fresh_blank_node synthesizes an anonymous node label ('b0', 'b1', …)
// in deterministic counter order; the label is interned for the
// parser's lifetime.
fresh_blank_node :: proc(p: ^Parser) -> rdf.Term {
	clear(&p.name_scratch)
	append(&p.name_scratch, 'b')
	write_int(&p.name_scratch, p.anon_counter)
	p.anon_counter += 1
	return rdf.Blank_Node(rdf.intern(&p.intern, string(p.name_scratch[:])))
}

@(private)
in_synthesized_namespace :: proc(label: string) -> bool {
	i := 0
	for i < len(label) && label[i] == 'B' {
		i += 1
	}
	if i >= len(label) || label[i] != 'b' {
		return false
	}
	i += 1
	if i >= len(label) {
		return false
	}
	for i < len(label) {
		if label[i] < '0' || label[i] > '9' {
			return false
		}
		i += 1
	}
	return true
}

@(private)
write_int :: proc(b: ^[dynamic]byte, value: int) {
	if value >= 10 {
		write_int(b, value / 10)
	}
	append(b, byte('0' + value % 10))
}

@(private)
resolve_iri_token :: proc(p: ^Parser, tok: Token) -> (iri: rdf.IRI, ok: bool) {
	term, tok_ok := iri_ref_term(p, tok)
	if !tok_ok {
		return "", false
	}
	return term.(rdf.IRI), true
}

// cow_unescape returns the token text as a borrowed slice when it has
// no escapes, and otherwise an unescaped copy owned by the parser until
// the current statement is freed.
@(private)
cow_unescape :: proc(p: ^Parser, tok: Token) -> string {
	if !tok.has_escape {
		return tok.text
	}
	b := make([dynamic]byte, 0, len(tok.text), p.allocator)
	decode_escapes(&b, tok.text)
	result := string(b[:])
	append(&p.owned, result)
	return result
}

// decode_escapes appends s with its ECHAR/UCHAR escapes decoded. The
// scanner validated every escape, so decoding cannot fail; the decoded
// form never exceeds the escaped form.
@(private)
decode_escapes :: proc(b: ^[dynamic]byte, s: string) {
	i := 0
	for i < len(s) {
		if s[i] != '\\' {
			append(b, s[i])
			i += 1
			continue
		}
		i += 1
		switch s[i] {
		case 't':
			append(b, '\t')
			i += 1
		case 'b':
			append(b, '\b')
			i += 1
		case 'n':
			append(b, '\n')
			i += 1
		case 'r':
			append(b, '\r')
			i += 1
		case 'f':
			append(b, '\f')
			i += 1
		case '"':
			append(b, '"')
			i += 1
		case '\'':
			append(b, '\'')
			i += 1
		case '\\':
			append(b, '\\')
			i += 1
		case 'u':
			append_codepoint(b, decode_hex(s[i + 1:i + 5]))
			i += 5
		case 'U':
			append_codepoint(b, decode_hex(s[i + 1:i + 9]))
			i += 9
		}
	}
}

@(private)
append_codepoint :: proc(b: ^[dynamic]byte, value: u32) {
	encoded, n := utf8.encode_rune(rune(value))
	append(b, ..encoded[:n])
}

@(private)
decode_hex :: proc(s: string) -> (value: u32) {
	for c in transmute([]byte)s {
		value <<= 4
		switch c {
		case '0' ..= '9':
			value |= u32(c - '0')
		case 'a' ..= 'f':
			value |= u32(c - 'a' + 10)
		case 'A' ..= 'F':
			value |= u32(c - 'A' + 10)
		}
	}
	return value
}

next_token :: proc(p: ^Parser) -> (Token, bool) {
	if p.has_lookahead {
		p.has_lookahead = false
		return p.lookahead, true
	}
	return scanner_next(&p.scanner)
}

peek_token :: proc(p: ^Parser) -> (Token, bool) {
	if !p.has_lookahead {
		tok, ok := scanner_next(&p.scanner)
		if !ok {
			return {}, false
		}
		p.lookahead = tok
		p.has_lookahead = true
	}
	return p.lookahead, true
}

// scanner_failed promotes a scanner error to the parser and reports
// whether one occurred; a clean end of input is not a failure.
scanner_failed :: proc(p: ^Parser) -> bool {
	if p.scanner.err.kind != .None {
		p.err = p.scanner.err
		return true
	}
	return false
}

fail_at :: proc(p: ^Parser, kind: Error_Kind, tok: Token) {
	p.err = {
		kind   = kind,
		offset = tok.offset,
		line   = tok.line,
		column = tok.column,
	}
}

// fail_here reports an error at the current scanner position (end of
// input reached while a statement was incomplete).
fail_here :: proc(p: ^Parser, kind: Error_Kind) {
	p.err = {
		kind   = kind,
		offset = p.scanner.pos,
		line   = p.scanner.line,
		column = p.scanner.pos - p.scanner.line_start + 1,
	}
}
