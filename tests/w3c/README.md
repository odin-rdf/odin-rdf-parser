# Vendored W3C RDF test suites

Official conformance test suites for the line-based RDF formats, vendored
so the harness runs hermetically with no network access.

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

Per the upstream README, RDF 1.2 conformance is determined by the RDF 1.2
suites **together with** the relevant RDF 1.1 suites — hence all four are
vendored. The `c14n/` canonicalization suites and `reports/` directories
are intentionally excluded (out of scope for syntax conformance).

The harness lives in `harness/` and runs under `odin test`. Its manifest
reader handles only the restricted Turtle subset these manifests use —
it is test infrastructure, not a Turtle parser, and will be replaced when
the real Turtle parser lands.
