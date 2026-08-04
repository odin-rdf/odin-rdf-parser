# Vendored W3C RDF test suites

Official conformance test suites for the RDF syntaxes this library
implements, vendored so the harness runs hermetically with no network
access.

- **Source**: https://github.com/w3c/rdf-tests
- **Upstream commit**: `767554e135eb6665949d870e6fa7bbc813837293` (main)
- **Retrieved**: 2026-08-04
- **License**: W3C Test Suite License / W3C 3-clause BSD License (see the
  header of each `manifest.ttl`)

| Directory | Upstream path | Contents |
|---|---|---|
| `rdf11-ntriples/` | `rdf/rdf11/rdf-n-triples/` | RDF 1.1 N-Triples syntax tests |
| `rdf11-nquads/` | `rdf/rdf11/rdf-n-quads/` | RDF 1.1 N-Quads syntax tests |
| `rdf12-ntriples-syntax/` | `rdf/rdf12/rdf-n-triples/syntax/` | RDF 1.2 N-Triples syntax tests (triple terms, base direction) |
| `rdf12-nquads-syntax/` | `rdf/rdf12/rdf-n-quads/syntax/` | RDF 1.2 N-Quads syntax tests |
| `rdf11-turtle/` | `rdf/rdf11/rdf-turtle/` | RDF 1.1 Turtle syntax + eval tests |
| `rdf11-trig/` | `rdf/rdf11/rdf-trig/` | RDF 1.1 TriG syntax + eval tests |
| `rdf12-turtle-syntax/` | `rdf/rdf12/rdf-turtle/syntax/` | RDF 1.2 Turtle syntax tests (RDF-star, version directive) |
| `rdf12-turtle-eval/` | `rdf/rdf12/rdf-turtle/eval/` | RDF 1.2 Turtle eval tests |
| `rdf12-trig-syntax/` | `rdf/rdf12/rdf-trig/syntax/` | RDF 1.2 TriG syntax tests |
| `rdf12-trig-eval/` | `rdf/rdf12/rdf-trig/eval/` | RDF 1.2 TriG eval tests |

Per the upstream README, RDF 1.2 conformance is determined by the RDF 1.2
suites **together with** the relevant RDF 1.1 suites — hence both
generations are vendored. The `c14n/` canonicalization suites, `reports/`
directories, and TESTS archives are intentionally excluded (out of scope
for syntax conformance).

The harness lives in `harness/` and runs under `odin test`. Eval tests
compare the parsed dataset against the expected N-Triples/N-Quads file
(parsed with this library's own line-based parsers) up to a blank-node
bijection — see `harness/compare.odin`. Each test's base IRI is the
suite's `mf:assumedTestBase` plus the action file name. The manifest
reader handles only the restricted Turtle subset these manifests use —
it is test infrastructure, not a Turtle parser, and will be replaced when
the real Turtle parser lands (RDF-T-0020).
