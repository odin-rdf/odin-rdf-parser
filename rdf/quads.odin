package rdf

// Graph_Label names the graph a quad belongs to. Only an IRI or a blank
// node may name a graph; a nil Graph_Label denotes the default graph.
Graph_Label :: union {
	IRI,
	Blank_Node,
}

// Quad is an RDF quad: a triple plus the graph it belongs to. The triple
// is embedded with `using`, so a Quad is usable wherever triple fields
// are expected.
Quad :: struct {
	using triple: Triple,
	graph:        Graph_Label,
}
