// The README quick-start examples, compiled and asserted here so the
// documentation cannot drift from the real API.
package readme

import "core:io"
import "core:strings"
import "core:testing"

import rdf "../../rdf"
import turtle "../../rdf/turtle"

README_SOURCE :: `
@prefix ex: <http://example.org/> .

ex:alice a ex:Person ;
    ex:name "Alice"@en .
`

@(test)
readme_parse_example :: proc(t: ^testing.T) {
	p: turtle.Parser
	turtle.parser_init(&p, transmute([]byte)string(README_SOURCE))
	defer turtle.parser_destroy(&p)

	count := 0
	for {
		triple, ok := turtle.parser_next(&p)
		if !ok {
			break
		}
		_ = triple // valid until the statement is drained; clone/intern to keep
		count += 1
	}
	testing.expect_value(t, p.err.kind, turtle.Error_Kind.None)
	testing.expect_value(t, count, 2)
}

// write_alice is the README emit example, verbatim.
write_alice :: proc(w: io.Writer) -> io.Error {
	prefixes := []turtle.Prefix{{"ex", "http://example.org/"}}
	e: turtle.Emitter
	turtle.emitter_init(&e, w, prefixes) or_return
	defer turtle.emitter_destroy(&e)

	alice := rdf.IRI("http://example.org/alice")
	turtle.emit(&e, {alice, rdf.RDF_TYPE, rdf.IRI("http://example.org/Person")}) or_return
	turtle.emit(&e, {alice, rdf.IRI("http://example.org/name"), rdf.literal("Alice", "en")}) or_return
	return turtle.emitter_finish(&e)
}

@(test)
readme_emit_example :: proc(t: ^testing.T) {
	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	err := write_alice(strings.to_writer(&b))
	testing.expect_value(t, err, io.Error.None)

	expected :=
		"@prefix ex: <http://example.org/> .\n" +
		"ex:alice a ex:Person ;\n" +
		"    ex:name \"Alice\"@en .\n"
	testing.expect_value(t, strings.to_string(b), expected)
}
