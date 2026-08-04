package ttl

// Token_Kind enumerates the terminals of the Turtle and TriG grammars
// (W3C RDF 1.2), including the RDF-star surface.
Token_Kind :: enum {
	Invalid,
	IRI_Ref, // <...>, text without the angle brackets
	PName, // prefixed name incl. the colon; split at the FIRST colon
	Blank_Node_Label, // _:label, text without the "_:" prefix
	String_Literal, // any of the four quoted forms, delimiters stripped
	Lang_Tag, // @tag, text without the "@"; direction suffix included
	Integer, // INTEGER, full lexical form incl. sign
	Decimal, // DECIMAL
	Double, // DOUBLE
	Boolean, // 'true' or 'false'
	A, // the keyword 'a' (rdf:type)
	At_Prefix, // @prefix
	At_Base, // @base
	At_Version, // @version (RDF 1.2)
	Sparql_Prefix, // PREFIX (case-insensitive)
	Sparql_Base, // BASE (case-insensitive)
	Sparql_Version, // VERSION (case-insensitive; RDF 1.2)
	Graph_Keyword, // GRAPH (case-insensitive; TriG only)
	Datatype_Marker, // ^^
	Dot, // .
	Semicolon, // ;
	Comma, // ,
	L_Bracket, // [
	R_Bracket, // ]
	L_Paren, // (
	R_Paren, // )
	L_Brace, // { (TriG)
	R_Brace, // } (TriG)
	Reified_Open, // <<
	Reified_Close, // >>
	Triple_Term_Open, // <<(
	Triple_Term_Close, // )>>
	Annotation_Open, // {|
	Annotation_Close, // |}
	Tilde, // ~
}

// Token is one terminal. text is a borrowed slice of the source buffer
// with delimiters stripped (except PName, which keeps its colon); it is
// valid as long as the source is. has_escape marks \-escapes only —
// percent encodings in local names are content, never decoded.
Token :: struct {
	kind:        Token_Kind,
	text:        string,
	offset:      int, // byte offset of the token start (incl. delimiters)
	line:        int, // 1-based
	column:      int, // 1-based, in bytes
	has_escape:  bool,
	long_string: bool, // String_Literal came from a long ("""/''') form
}
