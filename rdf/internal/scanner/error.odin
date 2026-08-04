package scanner

// Error_Kind enumerates grammar violations for the line-based formats.
// Parser-level kinds live here too so rdf/triples and rdf/quads share a
// single Error type with the scanner.
Error_Kind :: enum {
	None,
	// Scanner-level.
	Unexpected_Character,
	Unterminated_IRI,
	Invalid_IRI_Character,
	Unterminated_String,
	Invalid_String_Character,
	Invalid_Blank_Node_Label,
	Invalid_Lang_Tag,
	Invalid_Escape,
	// Scanner-level, Turtle-family formats (set by rdf/internal/ttl).
	Unterminated_Long_String,
	Invalid_Number,
	Unknown_Keyword,
	Invalid_Percent_Encoding,
	// Parser-level (set by rdf/triples and rdf/quads).
	Expected_Subject,
	Expected_Predicate,
	Expected_Object,
	Expected_Dot,
	Expected_Datatype,
	Relative_IRI,
	Reserved_Datatype,
	Invalid_Graph_Label,
	Unclosed_Triple_Term,
	Invalid_Direction,
}

// Error is a grammar violation with its position. The zero value (kind
// .None) means no error.
Error :: struct {
	kind:   Error_Kind,
	offset: int, // byte offset into the source
	line:   int, // 1-based
	column: int, // 1-based, in bytes
}

// error_message returns a static description of the error kind,
// referencing the violated grammar production by name (production names
// are stable across RDF spec revisions, unlike their numbers). Position
// formatting is the caller's concern; this never allocates.
error_message :: proc(kind: Error_Kind) -> string {
	switch kind {
	case .None:
		return "no error"
	case .Unexpected_Character:
		return "unexpected character (ntriplesDoc)"
	case .Unterminated_IRI:
		return "unterminated IRI reference (IRIREF)"
	case .Invalid_IRI_Character:
		return "character not allowed in IRI reference (IRIREF)"
	case .Unterminated_String:
		return "unterminated string literal (STRING_LITERAL_QUOTED)"
	case .Invalid_String_Character:
		return "raw newline in string literal; use \\n or \\r (STRING_LITERAL_QUOTED)"
	case .Invalid_Blank_Node_Label:
		return "malformed blank node label (BLANK_NODE_LABEL)"
	case .Invalid_Lang_Tag:
		return "malformed language tag (LANGTAG)"
	case .Invalid_Escape:
		return "invalid escape sequence (ECHAR/UCHAR/PN_LOCAL_ESC)"
	case .Unterminated_Long_String:
		return "unterminated long string literal (STRING_LITERAL_LONG_QUOTE)"
	case .Invalid_Number:
		return "malformed numeric literal (INTEGER/DECIMAL/DOUBLE)"
	case .Unknown_Keyword:
		return "unknown keyword; expected 'a', 'true', 'false', PREFIX, BASE, or GRAPH (turtleDoc)"
	case .Invalid_Percent_Encoding:
		return "malformed percent encoding in local name (PERCENT)"
	case .Expected_Subject:
		return "expected IRI or blank node as subject (subject)"
	case .Expected_Predicate:
		return "expected IRI as predicate (predicate)"
	case .Expected_Object:
		return "expected IRI, blank node, literal, or triple term as object (object)"
	case .Expected_Dot:
		return "expected '.' after statement (triple)"
	case .Expected_Datatype:
		return "expected IRI after '^^' (literal)"
	case .Relative_IRI:
		return "relative IRI; IRIs must be absolute (IRIREF)"
	case .Reserved_Datatype:
		return "rdf:langString and rdf:dirLangString require language-tag syntax (literal)"
	case .Invalid_Graph_Label:
		return "expected IRI or blank node as graph label (graphLabel)"
	case .Unclosed_Triple_Term:
		return "triple term not closed with ')>>' (tripleTerm)"
	case .Invalid_Direction:
		return "base direction must be 'ltr' or 'rtl' (LANG_DIR)"
	}
	return "unknown error"
}
