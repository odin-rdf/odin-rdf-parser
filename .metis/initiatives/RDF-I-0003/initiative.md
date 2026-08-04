---
id: turtle-trig-parsers-and-emitters
level: initiative
title: "Turtle & TriG Parsers and Emitters"
short_code: "RDF-I-0003"
created_at: 2026-08-04T14:15:09.787659+00:00
updated_at: 2026-08-04T14:15:09.787659+00:00
parent: RDF-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/discovery"


exit_criteria_met: false
estimated_complexity: L
initiative_id: turtle-trig-parsers-and-emitters
---

# Turtle & TriG Parsers and Emitters Initiative

## Context

Third initiative under the [[odin-rdf-parser]] vision (RDF-V-0001), building on the completed Core RDF Data Model (RDF-I-0001) and the line-based parsers (RDF-I-0002, 100% W3C-conformant). It implements the two human-readable formats: **Turtle** (the most widely used RDF serialization) and **TriG** (Turtle plus named graph blocks), per their W3C RDF 1.2 grammars including RDF-star.

This is where the ADR RDF-A-0001 architecture meets its allocating cases: prefixed names (`foaf:name`) expand against the prefix map, relative IRIs resolve against the base, and both go through the intern table so each distinct IRI materializes once per parse. Everything else keeps the zero-copy discipline proven in RDF-I-0002. The parsers remain hand-written recursive descent — Turtle's nested structures (collections, blank node property lists, annotation blocks) are exactly what the ADR anticipated.

Proven infrastructure carries over: the statement-level memory management and error model from `rdf/internal/statement`, the escaping core in `rdf/internal/emit`, the W3C harness in `tests/w3c` (built format-agnostic for this moment), and the allocation-guard/benchmark machinery.

## Goals & Non-Goals

**Goals:**
- **Turtle parser** (`rdf/turtle`) conforming to the W3C RDF 1.2 grammar: `@prefix`/`@base` and SPARQL-style `PREFIX`/`BASE` directives, prefixed names, relative IRI resolution, the `a` keyword, predicate lists (`;`) and object lists (`,`), blank node property lists `[ ]`, collections `( )`, all string forms (single/double-quoted, long strings), numeric and boolean literals, and the RDF 1.2 additions (triple terms, reifiers, annotation syntax — exact scope confirmed against the W3C suite during design).
- **TriG parser** (`rdf/trig`): Turtle extended with graph blocks, yielding `rdf.Quad`s; same API shape as `rdf/quads`.
- Same public API idiom as the line-based packages: `parser_init`/`parser_next`/`parser_destroy`, sticky structured errors, per-statement validity contract with prefix-expanded IRIs owned by the parser's intern table.
- **Emitters** for both formats producing spec-valid output; scope of abbreviation (flat vs prefix-aware) decided during design.
- **W3C conformance**: vendor and pass the official Turtle and TriG suites (RDF 1.1 + RDF 1.2) through the existing harness — including **eval tests**, which compare parsed output against expected N-Triples/N-Quads and therefore need blank-node-isomorphism comparison in the harness.
- **Replace the hand-rolled manifest reader** in `tests/w3c/harness` with the real Turtle parser (retiring the debt recorded in RDF-T-0010).
- Extend allocation guards and benchmarks: prefixed-name-heavy corpora, interning effectiveness (distinct-IRI count vs allocation count), throughput baselines.

**Non-Goals:**
- Pretty-printing heuristics beyond the chosen emitter scope (no smart grouping/indentation engine unless design decides a minimal one is cheap).
- RDF/XML, JSON-LD, N3 (out of scope per the vision).
- Datatype value semantics (numeric literals are captured lexically with the correct datatype IRI, not evaluated).
- Full RFC 3987 IRI validation (same scheme-level check as RDF-I-0002).

## Detailed Design

To be developed during design. Known shape and open questions:

- **Scanner**: Turtle's lexical ground differs enough from the line-based formats (prefixed-name productions, keywords, numbers, three extra string forms, `[ ] ( ) ; ,` punctuation) that a second scanner in `rdf/internal` is expected, sharing the escape-validation and position primitives; confirm whether sharing code or sharing only conventions is cleaner.
- **Parser state**: prefix map + base + intern table lifetime (per-parser, per ADR); how expanded IRIs interact with the per-statement free discipline — interned strings must outlive statements, unlike CoW unescapes. Likely: intern table owns expansions for the parser's lifetime, per RDF-A-0001.
- **Anonymous blank nodes**: `[ ]` and collections require parser-synthesized labels; scheme must avoid colliding with document labels (e.g., a reserved prefix) and stay deterministic for tests.
- **Relative IRI resolution**: RFC 3986 merge/normalize algorithm — implemented once in an internal package, allocating from the intern table.
- **Statement buffering**: one Turtle subject can produce many triples (property lists, collections); `parser_next` yields them one at a time, so the parser needs a small statement queue — decide its memory discipline.
- **Eval-test comparison**: harness needs graph comparison with blank-node bijection (the W3C eval tests' expected results are N-Triples/N-Quads files, parsed with the RDF-I-0002 parsers — a nice dogfooding loop). Deterministic-label mapping first, full isomorphism only if the suites require it.
- **Emitter scope**: flat spec-valid output (full IRIs, one triple per statement) vs prefix-aware abbreviation — decide with an eye on the round-trip property.
- **RDF 1.2 surface**: confirm which star features (triple terms `<<( )>>`, reified triples `<< >>`, annotations `{| |}`, reifier syntax `~`) the current W3C Turtle 1.2 suite exercises and scope accordingly.

## Alternatives Considered

Architecture-level alternatives were settled in ADRs RDF-A-0001/0002 and are not revisited. Local alternatives (scanner sharing, blank-node labeling, emitter abbreviation, isomorphism strategy) will be recorded here as design resolves them.

## Implementation Plan

1. **Design**: resolve the open questions above; likely no new ADR needed unless the statement-queue or interning design proves architectural.
2. **Turtle scanner**: internal package with unit tests.
3. **Turtle parser — terms & directives**: prefixes, base, IRI resolution, simple triples.
4. **Turtle parser — structures**: predicate/object lists, blank node property lists, collections, string forms, numeric/boolean literals.
5. **Turtle parser — RDF 1.2**: triple terms and the confirmed star surface.
6. **TriG parser**: graph blocks over the Turtle core.
7. **Emitters** for both formats with round-trip tests.
8. **W3C suites**: vendor Turtle/TriG suites, extend the harness with eval-test comparison, pass 100%.
9. **Harness debt**: replace the hand-rolled manifest reader with the real Turtle parser.
10. **Guards & benchmarks**: interning-aware allocation guards and throughput baselines.

Tasks will be created once this initiative reaches the ready phase.