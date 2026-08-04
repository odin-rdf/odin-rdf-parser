package rdf

// Constructors below are the supported way to build a Literal: they
// enforce the datatype/language/direction invariants documented on the
// type, which the type system cannot express. None of them allocate.

// literal builds a Literal from any of the supported shapes:
//   literal(lexical)                        -> plain literal (xsd:string)
//   literal(lexical, language)              -> language-tagged (rdf:langString)
//   literal(lexical, language, direction)   -> directional (rdf:dirLangString)
//
// Typed literals are built with literal_typed, which stays out of this
// group: an untyped string argument would match both string and IRI,
// making literal("x", "en") ambiguous.
literal :: proc {
	literal_plain,
	literal_lang,
	literal_dir_lang,
}

// literal_plain returns a plain literal; its datatype is xsd:string.
literal_plain :: proc(lexical: string) -> Literal {
	return {lexical = lexical, datatype = XSD_STRING}
}

// literal_typed returns a literal with an explicit datatype. The datatype
// must not be rdf:langString or rdf:dirLangString — those require a
// language tag; use literal_lang or literal_dir_lang instead.
literal_typed :: proc(lexical: string, datatype: IRI) -> Literal {
	assert(datatype != RDF_LANG_STRING && datatype != RDF_DIR_LANG_STRING,
		"language-tagged literals must be built with literal_lang or literal_dir_lang")
	return {lexical = lexical, datatype = datatype}
}

// literal_lang returns a language-tagged literal; its datatype is
// rdf:langString. The language tag must be non-empty (BCP 47, stored as
// given — not validated or case-normalized here).
literal_lang :: proc(lexical: string, language: string) -> Literal {
	assert(language != "", "language-tagged literal requires a non-empty language tag")
	return {lexical = lexical, datatype = RDF_LANG_STRING, language = language}
}

// literal_dir_lang returns a directional language-tagged literal (RDF 1.2);
// its datatype is rdf:dirLangString. Both a non-empty language tag and a
// direction other than .None are required.
literal_dir_lang :: proc(lexical: string, language: string, direction: Direction) -> Literal {
	assert(language != "", "directional literal requires a non-empty language tag")
	assert(direction != .None, "directional literal requires a direction")
	return {lexical = lexical, datatype = RDF_DIR_LANG_STRING, language = language, direction = direction}
}
