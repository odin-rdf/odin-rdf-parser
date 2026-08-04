// Package w3c runs the vendored W3C conformance suites against the
// parsers. The manifest reader below handles only the restricted Turtle
// subset the official manifests use (line-oriented entry blocks) — it is
// test infrastructure, not a Turtle parser, and gets replaced when the
// real Turtle parser lands.
package w3c

import "core:strings"

Entry :: struct {
	id:       string, // e.g. "trs:ntriples12-01"
	name:     string, // mf:name
	type_str: string, // e.g. "rdft:TestNTriplesPositiveSyntax"
	action:   string, // input file name relative to the suite directory
}

// parse_manifest extracts test entries from a manifest.ttl. An entry
// begins on a line of the form `<id> rdf:type rdft:Test... ;` and is
// completed by its `mf:action <file>` line. Lines outside entry blocks
// (prefixes, the mf:entries list, manifest metadata) carry no
// `rdft:Test` type and are ignored.
parse_manifest :: proc(source: string, allocator := context.allocator) -> [dynamic]Entry {
	entries := make([dynamic]Entry, allocator)
	current: Entry
	in_entry := false

	remaining := source
	for line_raw in strings.split_lines_iterator(&remaining) {
		line := strings.trim_space(line_raw)
		if line == "" || strings.has_prefix(line, "#") {
			continue
		}

		if strings.contains(line, "rdft:Test") &&
		   (strings.contains(line, "rdf:type") || strings.contains(line, " a ")) {
			if in_entry && current.action != "" {
				append(&entries, current)
			}
			current = {}
			in_entry = true

			fields := strings.fields(line, context.temp_allocator)
			if len(fields) > 0 {
				current.id = fields[0]
			}
			for f in fields {
				if strings.has_prefix(f, "rdft:Test") {
					current.type_str = strings.trim_suffix(f, ";")
					break
				}
			}
			continue
		}

		if !in_entry {
			continue
		}
		if strings.contains(line, "mf:name") {
			if open := strings.index_byte(line, '"'); open >= 0 {
				if close := strings.last_index_byte(line, '"'); close > open {
					current.name = line[open + 1:close]
				}
			}
		} else if strings.contains(line, "mf:action") {
			if open := strings.index_byte(line, '<'); open >= 0 {
				if close := strings.index_byte(line, '>'); close > open {
					current.action = line[open + 1:close]
				}
			}
		}
	}
	if in_entry && current.action != "" {
		append(&entries, current)
	}
	return entries
}
