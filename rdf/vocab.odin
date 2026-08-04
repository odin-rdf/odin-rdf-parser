package rdf

// Well-known IRIs the data model itself needs, plus a minimal set of
// common terms used by the RDF grammars (Turtle collections, RDF 1.2
// reification). Full vocabulary packages are a downstream concern.

// RDF_NS is the rdf: namespace.
RDF_NS :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
// XSD_NS is the xsd: namespace.
XSD_NS :: "http://www.w3.org/2001/XMLSchema#"

// XSD_STRING is the datatype of plain literals.
XSD_STRING :: IRI(XSD_NS + "string")
// RDF_LANG_STRING is the datatype of language-tagged literals.
RDF_LANG_STRING :: IRI(RDF_NS + "langString")
// RDF_DIR_LANG_STRING is the datatype of directional language-tagged
// literals (RDF 1.2).
RDF_DIR_LANG_STRING :: IRI(RDF_NS + "dirLangString")

// RDF_TYPE is rdf:type (the Turtle keyword "a").
RDF_TYPE :: IRI(RDF_NS + "type")
// RDF_NIL terminates RDF collections.
RDF_NIL :: IRI(RDF_NS + "nil")
// RDF_FIRST is the head of an RDF collection cell.
RDF_FIRST :: IRI(RDF_NS + "first")
// RDF_REST is the tail of an RDF collection cell.
RDF_REST :: IRI(RDF_NS + "rest")
// RDF_REIFIES relates a reifier to a triple term (RDF 1.2).
RDF_REIFIES :: IRI(RDF_NS + "reifies")

// Datatypes of the Turtle abbreviated literal forms (numeric and
// boolean literals are captured lexically with these datatypes).
XSD_INTEGER :: IRI(XSD_NS + "integer")
XSD_DECIMAL :: IRI(XSD_NS + "decimal")
XSD_DOUBLE :: IRI(XSD_NS + "double")
XSD_BOOLEAN :: IRI(XSD_NS + "boolean")
