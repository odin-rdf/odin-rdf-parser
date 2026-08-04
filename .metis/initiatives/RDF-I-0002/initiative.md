---
id: n-triples-n-quads-parsers-and
level: initiative
title: "N-Triples & N-Quads Parsers and Emitters"
short_code: "RDF-I-0002"
created_at: 2026-08-04T11:02:46.211117+00:00
updated_at: 2026-08-04T11:02:46.211117+00:00
parent: RDF-V-0001
blocked_by: ["RDF-I-0001"]
archived: false

tags:
  - "#initiative"
  - "#phase/discovery"


exit_criteria_met: false
estimated_complexity: M
initiative_id: n-triples-n-quads-parsers-and
---

# N-Triples & N-Quads Parsers and Emitters Initiative

## Context

Second initiative under the [[odin-rdf-parser]] vision (RDF-V-0001), and the first parser work. It implements parsers and emitters for the two line-based formats — N-Triples and N-Quads (a quad is a triple plus an optional graph label, so the two grammars share almost everything) — including their RDF-star triple-term syntax.

Parser style is fixed by **ADR RDF-A-0001**: hand-written streaming pull parser over caller-owned `[]byte`, borrowed slices by default, copy-on-write only for escape sequences, per-statement validity contract. The line-based formats have no prefixes and no relative IRIs, so they exercise the *fully* zero-copy path — this initiative is where the zero-copy discipline gets proven before Turtle/TriG add the allocating cases.

**Depends on RDF-I-0001 (Core RDF Data Model)**: parsers yield and emitters consume the term/triple/quad types defined there. This initiative cannot leave design until the data model's public types are stable.

## Goals & Non-Goals

**Goals:**
- N-Triples parser and N-Quads parser conforming to the W3C RDF 1.2 grammars, including triple terms (RDF-star), sharing a common scanner/statement core.
- N-Triples and N-Quads emitters producing spec-valid output, with correct escaping (the inverse of the parser's unescaping).
- Zero-copy behavior per ADR RDF-A-0001: no allocation for statements without escape sequences; copy-on-write unescaping otherwise.
- Precise, spec-referencing error reporting with line/column positions; a malformed line fails cleanly without corrupting parser state.
- A W3C test-suite harness (manifest reader + runner) that executes the official N-Triples and N-Quads suites, including the negative-syntax and RDF-star cases. The harness is built to be reused by the later Turtle/TriG initiative.
- Round-trip tests: parse → emit → parse yields equal statements.
- Benchmarks guarding the zero-copy fast path (allocation counts, throughput) so accidental copies are caught as regressions.

**Non-Goals:**
- Turtle and TriG (next initiative; they layer prefix/base/interning on the same core).
- Incremental refill sources (statements straddling a buffer window) — per the ADR this is a source-adapter concern; whole-statement-in-buffer is acceptable here.
- Any graph/dataset container, canonicalization, or blank-node isomorphism checking beyond what the test harness minimally needs to compare expected results.
- Pretty-printing or serialization options beyond spec-conformant output (e.g., no sorting, no alignment).

## Detailed Design

To be developed during design. Known shape and open questions:

- **Shared core**: one scanner and statement parser parameterized (or lightly branched) over triple-vs-quad; N-Triples is effectively N-Quads minus the graph label. **Package split resolved in RDF-I-0001's design**: two thin packages — `rdf/triples` (N-Triples) and `rdf/quads` (N-Quads) — over a shared internal scanner package, importing the core model via `import rdf ".."`.
- **API surface**: `parser_init(source: []byte, allocator)` / `parser_next` / `parser_destroy`, mirrored by `emitter` procedures writing to an `io.Writer` or `[]byte` builder — exact shape to align with data-model conventions from RDF-I-0001.
- **Escape handling**: scanner records whether a token contains `\`; unescape-on-yield only then. Emitter side: minimal mandatory escaping per spec.
- **Error model**: error value with byte offset, line/column, and the violated grammar production; decide Odin idiom (enum + details struct vs. message string).
- **Test harness**: reads the W3C manifest format; vendored copies of the official test suites live in the repo (they are static W3C artifacts, not a code dependency).

## Alternatives Considered

Parser architecture alternatives were analyzed and settled in ADR RDF-A-0001; they are not revisited here. Remaining local alternatives (single shared package vs. per-format packages, error-model shape) will be recorded as this section fills in during design.

## Implementation Plan

1. **Design**: settle shared-core layout, API naming against the data model, and error model.
2. **N-Triples parser**: scanner + statement parser + unescaping; unit tests.
3. **N-Quads parser**: graph-label extension over the shared core; unit tests.
4. **Emitters**: N-Triples and N-Quads with escaping; round-trip tests.
5. **W3C harness**: manifest runner; pass both official suites including RDF-star cases.
6. **Benchmarks**: allocation and throughput guards for the zero-copy path.

Tasks will be created once this initiative reaches the ready phase; steps 2–6 depend on RDF-I-0001 delivering stable term/triple/quad types.