// Package corpus generates deterministic N-Triples/N-Quads documents for
// benchmarks and allocation guards. Output is a pure function of the
// arguments so numbers are comparable across runs.
package corpus

import "core:fmt"
import "core:strings"

// generate_triples produces n statements cycling through term shapes.
// When escaped is true, every statement's object is a literal containing
// exactly one escape sequence — the basis for exact allocation-count
// guards (one copy-on-write unescape per statement).
generate_triples :: proc(n: int, escaped: bool, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for i in 0 ..< n {
		fmt.sbprintf(&b, "<http://example.org/subject/%d> <http://example.org/predicate/%d> ", i % 1000, i % 50)
		if escaped {
			fmt.sbprintf(&b, "\"value\\tnumber %d\" .\n", i)
		} else {
			switch i % 3 {
			case 0:
				fmt.sbprintf(&b, "<http://example.org/object/%d> .\n", i)
			case 1:
				fmt.sbprintf(&b, "\"plain value %d\" .\n", i)
			case 2:
				fmt.sbprintf(&b, "\"tagged value %d\"@en .\n", i)
			}
		}
	}
	return strings.to_string(b)
}

// generate_quads is generate_triples with the three graph-label cases
// (IRI, blank node, default graph) cycled in.
generate_quads :: proc(n: int, escaped: bool, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for i in 0 ..< n {
		fmt.sbprintf(&b, "<http://example.org/subject/%d> <http://example.org/predicate/%d> ", i % 1000, i % 50)
		if escaped {
			fmt.sbprintf(&b, "\"value\\tnumber %d\"", i)
		} else {
			fmt.sbprintf(&b, "\"plain value %d\"", i)
		}
		switch i % 3 {
		case 0:
			fmt.sbprintf(&b, " <http://example.org/graph/%d> .\n", i % 10)
		case 1:
			fmt.sbprintf(&b, " _:g%d .\n", i % 10)
		case 2:
			strings.write_string(&b, " .\n")
		}
	}
	return strings.to_string(b)
}
