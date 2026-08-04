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

// TURTLE_CYCLE is the statement cycle length of the Turtle/TriG
// corpora: statement i and statement i+TURTLE_CYCLE are byte-identical,
// so every distinct IRI appears within the first cycle — the basis for
// the interning guards' exact expectations.
TURTLE_CYCLE :: 1000

// TURTLE_DISTINCT_IRIS is the number of distinct IRIs generate_turtle
// materializes (given n >= TURTLE_CYCLE): subjects + two predicate
// families + objects + the interned prefix name and namespace IRI.
TURTLE_DISTINCT_IRIS :: TURTLE_CYCLE + 50 + 50 + 100 + 2

// generate_turtle produces n prefixed-name-heavy statements with ';'
// and ',' fan-out (3 triples per statement) and no blank nodes, fully
// cyclic with period TURTLE_CYCLE.
generate_turtle :: proc(n: int, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "@prefix ex: <http://example.org/> .\n")
	for i in 0 ..< n {
		fmt.sbprintf(
			&b,
			"ex:s%d ex:p%d ex:o%d ; ex:q%d \"v%d\"@en , true .\n",
			i % TURTLE_CYCLE,
			i % 50,
			i % 100,
			i % 50,
			i % TURTLE_CYCLE,
		)
	}
	return strings.to_string(b)
}

// generate_turtle_structures produces n structure-heavy statements —
// a blank node property list containing a two-element collection —
// yielding 6 triples per statement. Anonymous labels make interning
// grow with n by design (each synthesized label is a distinct string).
generate_turtle_structures :: proc(n: int, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "@prefix ex: <http://example.org/> .\n")
	for i in 0 ..< n {
		fmt.sbprintf(
			&b,
			"ex:s%d ex:p%d [ ex:q%d ( 1 2 ) ] .\n",
			i % TURTLE_CYCLE,
			i % 50,
			i % 50,
		)
	}
	return strings.to_string(b)
}

// generate_trig wraps the generate_turtle statement shape in cycling
// graph contexts: labeled block, default-graph block, and unwrapped —
// fully cyclic with period TURTLE_CYCLE.
generate_trig :: proc(n: int, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "@prefix ex: <http://example.org/> .\n")
	for i in 0 ..< n {
		switch i % 3 {
		case 0:
			fmt.sbprintf(&b, "ex:g%d ", i % 10)
			strings.write_string(&b, "{ ")
		case 1:
			strings.write_string(&b, "{ ")
		}
		fmt.sbprintf(
			&b,
			"ex:s%d ex:p%d ex:o%d ; ex:q%d \"v%d\"@en , true .",
			i % TURTLE_CYCLE,
			i % 50,
			i % 100,
			i % 50,
			i % TURTLE_CYCLE,
		)
		if i % 3 == 2 {
			strings.write_string(&b, "\n")
		} else {
			strings.write_string(&b, " }\n")
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
