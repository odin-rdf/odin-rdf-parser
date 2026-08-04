---
id: turtle-trig-parsers-and-emitters
level: initiative
title: "Turtle & TriG Parsers and Emitters"
short_code: "RDF-I-0003"
created_at: 2026-08-04T14:15:09.787659+00:00
updated_at: 2026-08-04T16:16:30.429259+00:00
parent: RDF-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/completed"


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
- **Emitters** for both formats producing spec-valid output with minimal prefix-aware abbreviation (caller-supplied prefix map, `a` keyword, `;`/`,` grouping via one-statement lookbehind; empty prefix map yields flat output).
- **W3C conformance**: vendor and pass the official Turtle and TriG suites (RDF 1.1 + RDF 1.2) through the existing harness — including **eval tests**, which compare parsed output against expected N-Triples/N-Quads and therefore need blank-node-isomorphism comparison in the harness.
- **Replace the hand-rolled manifest reader** in `tests/w3c/harness` with the real Turtle parser (retiring the debt recorded in RDF-T-0010).
- Extend allocation guards and benchmarks: prefixed-name-heavy corpora, interning effectiveness (distinct-IRI count vs allocation count), throughput baselines.

**Non-Goals:**
- Pretty-printing heuristics beyond the chosen emitter scope (no smart grouping/indentation engine unless design decides a minimal one is cheap).
- RDF/XML, JSON-LD, N3 (out of scope per the vision).
- Datatype value semantics (numeric literals are captured lexically with the correct datatype IRI, not evaluated).
- Full RFC 3987 IRI validation (same scheme-level check as RDF-I-0002).

## Detailed Design

Resolved in design review, 2026-08-04. The two scope-setting decisions (emitter scope, RDF 1.2 surface) were approved by Greger; the rest are technical resolutions to be validated during implementation.

- **Emitter scope (approved)**: prefix-aware, minimal. Emitters take a caller-supplied prefix map and abbreviate with prefixed names, the `a` keyword, and `;`/`,` grouping of consecutive same-subject/same-predicate statements via one-statement lookbehind — streaming, no buffering or smart-grouping engine. Passing an empty prefix map degrades gracefully to flat full-IRI output.
- **RDF 1.2 surface (approved)**: suite-driven. Implement the full published RDF 1.2 Turtle/TriG grammars (triple terms `<<( )>>`, reified triples `<< >>`, annotations `{| |}`, reifier `~`); the vendored W3C 1.2 suites define "done". Grammar surface no test exercises is still parsed and flagged as untested in task notes, not cut.
- **Scanner**: new scanner in `rdf/internal` reusing the escape-validation and position primitives as functions but sharing no scanner state machine — shared conventions, not shared code. Confirm against the full token inventory when the scanner task is drafted.
- **Parser state**: per RDF-A-0001 — the intern table owns prefix expansions and resolved IRIs for the parser's lifetime; CoW unescapes keep the per-statement free discipline. Remaining design work is documenting that boundary precisely, not choosing it.
- **Anonymous blank nodes**: parser-synthesized labels from a reserved internal scheme, with deterministic counter order for tests; document labels that collide are remapped (any label is a legal `BLANK_NODE_LABEL`, so avoidance alone can't work). Exact scheme picked in the parser task.
- **Relative IRI resolution**: RFC 3986 merge/normalize implemented once in an internal package, allocating from the intern table.
- **Statement buffering**: small growable triple queue owned by the parser, reset (not freed) per top-level statement — fan-out is bounded by the statement text, and `parser_next` stays allocation-free in steady state.
- **Eval-test comparison**: deterministic label mapping first; escalate to full blank-node isomorphism only if inspection of the vendored suites turns up tests that require it. Verify while vendoring the suites so the harness task is scoped by evidence.

## Alternatives Considered

Architecture-level alternatives were settled in ADRs RDF-A-0001/0002 and are not revisited. Local alternatives resolved in the 2026-08-04 design review:

- **Flat-only emitters** (full IRIs, one triple per line): rejected — output would be N-Triples with a `.ttl` extension, giving little reason to use the new emitters over the existing ones.
- **Flat now, abbreviation later** (backlog item): rejected — round-trip tests in this initiative would then exercise almost none of the Turtle grammar surface, weakening the conformance story.
- **Parse only what the W3C 1.2 suites test** (reject untested star constructs): rejected — "unsupported valid Turtle" is an awkward error class, and suite lag would create artificial gaps.
- **RDF 1.1 first, star in a follow-up**: rejected — the vision targets RDF 1.2 and the line-based parsers already handle triple terms; Turtle would trail its own siblings.

## Implementation Plan

1. **Design**: ✅ resolved 2026-08-04 (see Detailed Design); no new ADR needed — the statement-queue and interning designs stay within RDF-A-0001.
2. **Turtle scanner**: [[RDF-T-0012]]
3. **RFC 3986 relative IRI resolution**: [[RDF-T-0013]] — split out of the parser-core step as an independently testable internal package; parallel with RDF-T-0012.
4. **Turtle parser — terms & directives**: [[RDF-T-0014]]
5. **Turtle parser — structures**: [[RDF-T-0015]]
6. **Turtle parser — RDF 1.2**: [[RDF-T-0016]]
7. **TriG parser**: [[RDF-T-0017]]
8. **Emitters + round-trip tests**: [[RDF-T-0018]] — can start after RDF-T-0015.
9. **W3C suites + eval comparison**: [[RDF-T-0019]]
10. **Harness manifest-reader debt**: [[RDF-T-0020]] — sequenced after RDF-T-0019 so suite bring-up never depends on the parser under test.
11. **Guards & benchmarks**: [[RDF-T-0021]]

Critical path: RDF-T-0012 → 0014 → 0015 → 0016 → 0017 → 0019. Off-path: RDF-T-0013 (parallel with 0012), RDF-T-0018 (after 0015), RDF-T-0020/0021 (after 0019).

## Status Updates

**2026-08-04 — Decomposed into 10 tasks (RDF-T-0012 … RDF-T-0021).** Each task carries objective, acceptance criteria, approach, dependencies, and risks reflecting the design decisions above. Awaiting review and approval to transition to active.

**2026-08-04 — ALL 10 TASKS COMPLETED. Awaiting review for transition to completed.**

Delivered, in 8 commits (a27e8b3 … HEAD):
- `rdf/internal/ttl`: shared Turtle-family scanner + parser core + emitter core; `rdf/internal/iri`: RFC 3986 resolution.
- `rdf/turtle` and `rdf/trig`: parsers (full RDF 1.2 incl. the star surface and the VERSION directive) and prefix-aware emitters, both thin layers over the shared core.
- **Conformance: 100% — all 1045 tests across 10 vendored W3C suites** (213 line-based + 832 Turtle/TriG), including eval tests via blank-node-bijection graph comparison. Suite bring-up surfaced and fixed 4 real parser bugs (surrogate escapes, IRI escape smuggling, long-string closing rule, U+FFFD decoding).
- Harness manifest reader replaced with the real Turtle parser (RDF-T-0010 debt retired), with pinned per-suite entry counts guarding the circularity risk.
- Allocation guards prove steady-state-zero parsing and exact interning effectiveness (one table entry per distinct string); baselines: Turtle parse 7.2M triples/s, TriG 6.5M, emitters ~10.5M; prefix expansion + interning costs ~32% in statement rate vs the flat N-Triples path.

Two design refinements made during execution, both recorded in task notes: the blank-node collision scheme is remapping-based (document labels matching `^B*b[0-9]+$` get a `B` prepended) since grammar-level avoidance is impossible, and eval comparison went straight to full isomorphism because expected files are unordered and RDF graphs are sets (evidence: turtle12-eval-annotation-07).