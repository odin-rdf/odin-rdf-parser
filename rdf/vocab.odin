package rdf

// Well-known IRIs the data model itself needs, plus a minimal set of
// common terms used by the RDF grammars (Turtle collections, RDF 1.2
// reification). Full vocabulary packages are a downstream concern.

RDF_NS :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
XSD_NS :: "http://www.w3.org/2001/XMLSchema#"

// Datatypes referenced by the Literal invariants.
XSD_STRING          :: IRI(XSD_NS + "string")
RDF_LANG_STRING     :: IRI(RDF_NS + "langString")
RDF_DIR_LANG_STRING :: IRI(RDF_NS + "dirLangString")

// Common terms.
RDF_TYPE    :: IRI(RDF_NS + "type")
RDF_NIL     :: IRI(RDF_NS + "nil")
RDF_FIRST   :: IRI(RDF_NS + "first")
RDF_REST    :: IRI(RDF_NS + "rest")
RDF_REIFIES :: IRI(RDF_NS + "reifies")
