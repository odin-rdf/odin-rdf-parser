package scanner

// Token_Kind enumerates the terminals of the N-Triples/N-Quads grammars.
Token_Kind :: enum {
	Invalid,
	IRI_Ref,           // <...>, text without the angle brackets
	String_Literal,    // "...", text without the quotes
	Blank_Node_Label,  // _:label, text without the "_:" prefix
	Lang_Tag,          // @tag, text without the "@"; direction suffix included
	Datatype_Marker,   // ^^
	Dot,               // .
	Triple_Term_Open,  // <<(
	Triple_Term_Close, // )>>
}

// Token is one terminal. text is a borrowed slice of the source buffer
// with delimiters stripped; it is valid as long as the source is.
Token :: struct {
	kind:       Token_Kind,
	text:       string,
	offset:     int, // byte offset of the token start (incl. delimiters)
	line:       int, // 1-based
	column:     int, // 1-based, in bytes
	has_escape: bool, // content contains at least one \-escape
}
