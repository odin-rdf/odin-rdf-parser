---
id: n-triples-n-quads-parsers-and
level: initiative
title: "N-Triples & N-Quads Parsers and Emitters"
short_code: "RDF-I-0002"
created_at: 2026-08-04T11:02:46.211117+00:00
updated_at: 2026-08-04T14:09:50.265905+00:00
parent: RDF-V-0001
blocked_by: [RDF-I-0001]
archived: false

tags:
  - "#initiative"
  - "#phase/completed"


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

All design questions resolved (design session 2026-08-04):

- ~~**Shared core**~~ — **resolved**: two thin packages — `rdf/triples` (N-Triples) and `rdf/quads` (N-Quads) — over a shared internal scanner package, importing the core model via `import rdf ".."`.
- ~~**Parser API**~~ — **resolved**: scanner idiom, matching `core:bufio.Scanner`. `parser_init(p: ^Parser, source: []byte, allocator := context.allocator)`, then `parser_next(p) -> (stmt, ok: bool)` in a plain `for` loop; after the loop, `p.err` distinguishes clean EOF from a syntax error. `parser_destroy` releases copy-on-write allocations. Zero error plumbing per iteration; error details live on the parser where position state already is.
- ~~**Error model**~~ — **resolved**: `Error :: struct { kind: Error_Kind, offset: int, line: int, column: int }` with `Error_Kind` an enum of grammar violations, plus a formatting proc that renders the message with the spec production reference. Programmatic matching for the negative-syntax harness; no allocation.
- ~~**Emitter output**~~ — **resolved**: emitters write to `core:io`'s `io.Writer`. One code path for files, `strings.Builder`, and custom streams; matches `core:encoding/json` idiom. Emitter side does minimal mandatory escaping per spec (inverse of parser unescaping).
- **Escape handling** (per ADR RDF-A-0001): scanner records whether a token contains `\`; unescape-on-yield only then, from the parser's allocator.
- ~~**Test harness**~~ — **resolved**: official N-Triples/N-Quads suites vendored under `tests/w3c/` (static W3C artifacts; hermetic, offline-reproducible), downloaded once during the harness task with source URL and retrieval date recorded. Harness reads the W3C manifest format and is built for reuse by the Turtle/TriG initiative.

## Alternatives Considered

Parser architecture alternatives were analyzed and settled in ADR RDF-A-0001; they are not revisited here. Local alternatives considered in the 2026-08-04 design session: Go-style `(stmt, err)` iteration and three-way returns (rejected — per-iteration error plumbing, EOF-as-error un-idiomatic in Odin); enum-only and message-string errors (rejected — position lost off-parser / not matchable and allocating); `strings.Builder`-only emitters (rejected — forces whole-output buffering, contradicting the streaming principle); fetch-script and git-submodule test data (rejected — network-dependent tests / far more data and friction than needed).

## Implementation Plan

1. **Design**: settle shared-core layout, API naming against the data model, and error model.
2. **N-Triples parser**: scanner + statement parser + unescaping; unit tests.
3. **N-Quads parser**: graph-label extension over the shared core; unit tests.
4. **Emitters**: N-Triples and N-Quads with escaping; round-trip tests.
5. **W3C harness**: manifest runner; pass both official suites including RDF-star cases.
6. **Benchmarks**: allocation and throughput guards for the zero-copy path.

Tasks will be created once this initiative reaches the ready phase; steps 2–6 depend on RDF-I-0001 delivering stable term/triple/quad types.