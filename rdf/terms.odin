// Package rdf provides the core RDF 1.2 data model: terms, triples, and
// quads, including RDF-star triple terms.
//
// Lifetime contract (ADR RDF-A-0001): term strings are borrowed slices by
// default — typically views into the source buffer a parser was given. A
// value yielded by a parser is valid only until the next statement is
// pulled. Use clone or interning (RDF-T-0003) to promote a borrowed value
// to an owned one.
package rdf

// IRI is an absolute IRI as defined by RFC 3987. The lexical form is stored
// as given; no syntactic validation or normalization is performed.
IRI :: distinct string

// Blank_Node is a blank node label, stored WITHOUT the leading "_:" — the
// prefix is serialization syntax, not part of the node's identity.
Blank_Node :: distinct string

// Direction is the base direction of a directional language-tagged string
// (RDF 1.2). It is .None for every literal whose datatype is not
// rdf:dirLangString.
Direction :: enum u8 {
	None,
	LTR,
	RTL,
}

// Literal is an RDF literal.
//
// Invariants (enforced by the constructors in this package, not by the
// type system):
//   - datatype is always set; a plain literal has datatype xsd:string.
//   - language is non-empty if and only if datatype is rdf:langString or
//     rdf:dirLangString.
//   - direction is not .None if and only if datatype is rdf:dirLangString.
Literal :: struct {
	lexical:   string,
	datatype:  IRI,
	language:  string,
	direction: Direction,
}

// Term is an RDF term: exactly one of an IRI, a blank node, a literal, or
// an RDF-star triple term. A nil Term is not a valid RDF term.
//
// The ^Triple variant is the only term kind whose construction allocates.
// The type permits triple terms in any position; the RDF 1.2 grammars
// restrict them to the object position, which parsers enforce.
Term :: union {
	IRI,
	Blank_Node,
	Literal,
	^Triple,
}

// Triple is an RDF triple. Position validity (e.g. no literal subjects) is
// a grammar concern enforced by parsers, not by this type.
Triple :: struct {
	subject:   Term,
	predicate: Term,
	object:    Term,
}
