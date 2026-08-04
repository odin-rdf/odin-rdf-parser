# odin-rdf-parser

Streaming parsers and emitters for the core RDF serialization formats —
N-Triples, N-Quads, Turtle, and TriG — written in Odin with no external
dependencies. Implements the W3C RDF 1.2 grammars, including RDF-star
triple terms, and passes **all 1045 tests** of the vendored official W3C
conformance suites (RDF 1.1 and 1.2, syntax and eval).

This is deliberately a low-level library: it provides the primitives —
terms, triples, quads, parsing, serialization — on which triple/quad
stores, SPARQL engines, and other linked-data tooling can be built.
Those consumers, and other serializations (RDF/XML, JSON-LD, N3), are
out of scope and belong in downstream projects.

## Packages

| Package       | Description                                                                 |
| ------------- | --------------------------------------------------------------------------- |
| `rdf`         | Core data model: `IRI`, `Blank_Node`, `Literal`, `Term`, `Triple`, `Quad`; equality, hashing, cloning, interning; well-known vocabulary constants |
| `rdf/triples` | N-Triples parser and emitter (line-based, triples)                          |
| `rdf/quads`   | N-Quads parser and emitter (line-based, quads)                              |
| `rdf/turtle`  | Turtle parser and prefix-aware emitter (abbreviated, human-readable)        |
| `rdf/trig`    | TriG parser and prefix-aware emitter (Turtle plus named graph blocks)       |

All four format packages share the same API shape: `parser_init` /
`parser_next` / `parser_destroy` for parsing, `emitter_init` / `emit` /
`emitter_finish` / `emitter_destroy` for emitting (the line-based
formats emit statelessly with a plain `emit` proc). Doc comments on each
package carry the full contracts; start with `odin doc rdf` and
`odin doc rdf/turtle`.

## Quick start

Parsing Turtle into triples:

```odin
import turtle "rdf/turtle"

p: turtle.Parser
turtle.parser_init(&p, source) // source: []byte, the complete document
defer turtle.parser_destroy(&p)

for {
	triple, ok := turtle.parser_next(&p)
	if !ok {
		break
	}
	// use triple — valid until the statement is drained; rdf.clone or
	// rdf.intern_triple to keep it
}
if p.err.kind != .None {
	fmt.eprintfln("parse error at line %d, column %d: %s",
		p.err.line, p.err.column, turtle.error_message(p.err.kind))
}
```

Emitting triples as Turtle, to any `io.Writer`:

```odin
import rdf "rdf"
import turtle "rdf/turtle"

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
```

which writes:

```turtle
@prefix ex: <http://example.org/> .
ex:alice a ex:Person ;
    ex:name "Alice"@en .
```

Both examples are compiled and asserted in `tests/readme`. The other
three formats work the same way; `rdf/quads` and `rdf/trig` yield and
consume `rdf.Quad` (a nil `Graph_Label` is the default graph).

## Memory model

The parsers are streaming pull parsers with a zero-copy discipline
(ADR RDF-A-0001):

- **Input is the complete document** in one caller-owned `[]byte` that
  must stay valid and unmoved for the parser's lifetime. For large
  files, memory-map the file and pass the mapping — parser memory is
  bounded by nesting depth and the prefix map, never by document size,
  and no graph is ever materialized.
- **Term strings are borrowed slices** of the source buffer wherever the
  syntax allows; only escape sequences (copy-on-write unescaping) and
  Turtle/TriG prefix/base expansion (deduplicated in an intern table)
  allocate.
- **Statements are valid per-statement**: a yielded triple/quad is valid
  only until the next `parser_next` call (for Turtle/TriG, until its
  source statement is fully drained). To keep terms longer, promote them
  with `rdf.clone` (owned deep copy, released with `rdf.destroy`) or an
  `rdf.Intern_Table` (deduplicated, valid until `intern_table_destroy`).

Emitters write minimal, spec-valid output: mandatory escaping only, and
for Turtle/TriG optional prefix abbreviation, the `a` keyword, and
`;`/`,` grouping via one-statement lookbehind. An empty prefix map
yields flat full-IRI output.

## Conformance and testing

```sh
odin test rdf -all-packages   # unit tests for the model and all formats
odin test tests/w3c/harness   # the 10 vendored W3C suites (1045 tests)
odin test tests/guards        # allocation guards for the zero-copy paths
odin test tests/readme        # the examples above
odin run bench -o:speed       # throughput benchmarks
```

The W3C suites are vendored under `tests/w3c/` (static artifacts, so the
tests are hermetic and offline-reproducible); eval tests compare parsed
output against expected N-Triples/N-Quads under blank-node isomorphism.
The allocation guards prove that steady-state parsing allocates nothing
on escape-free input and that interning materializes each distinct IRI
exactly once per parse.

Representative throughput on an Apple-silicon laptop (see `bench/`):
N-Triples parse ~10M statements/s (~950 MB/s), Turtle parse ~7M
triples/s, TriG parse ~6.5M, Turtle/TriG emit ~10M.

## License

MIT — see [LICENSE](LICENSE).
