---
id: core-rdf-data-model
level: initiative
title: "Core RDF Data Model"
short_code: "RDF-I-0001"
created_at: 2026-08-04T09:30:01.147570+00:00
updated_at: 2026-08-04T12:31:19.306178+00:00
parent: RDF-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/active"


exit_criteria_met: false
estimated_complexity: M
initiative_id: core-rdf-data-model
---

# Core RDF Data Model Initiative

## Context

This is the first initiative under the [[odin-rdf-parser]] vision (RDF-V-0001). Every parser, emitter, and downstream consumer (triple/quad stores, SPARQL engines) will build on the types defined here, so this initiative establishes the shared vocabulary for the whole library: RDF terms, triples, quads, and their supporting operations, including RDF-star triple terms per RDF 1.2.

**Explicitly deferred**: This initiative contains **no parsing or lexing work**. Parser style has since been decided in ADR RDF-A-0001 (streaming pull parser, zero-copy borrowed slices) and parser work lives in its own initiative. If any task in this initiative appears to require parsing (e.g., validating lexical forms of IRIs or literals), that task must be flagged and the scope boundary revisited rather than quietly absorbing parser decisions.

## Goals & Non-Goals

**Goals:**
- Define Odin types for all RDF terms: IRIs, blank nodes, literals (with datatype IRIs and language tags), and RDF-star triple terms.
- Define triple and quad types (quad = triple + graph label) composed from those terms.
- Provide core operations: construction, equality comparison, hashing, and cloning/destruction consistent with Odin's explicit memory management.
- Establish the allocator-awareness conventions (who owns term strings, how documents/graphs own their terms) that all later initiatives will follow.
- Provide well-known constant vocabularies needed by the model itself (e.g., `rdf:langString`, `xsd:string` datatype IRIs).
- Unit tests covering construction, equality, hashing, and memory ownership for all term kinds, including nested triple terms.

**Non-Goals:**
- Parsing or emitting any serialization format — deferred until parser style is decided.
- Syntactic validation of IRIs or literal lexical forms (this borders on parsing; terms store what they are given).
- Graph/dataset containers with indexing or matching (that is triple-store territory per the vision's constraints; at most a simple dynamic array of triples/quads for tests).
- Datatype value semantics (numeric comparison, `xsd:integer` canonicalization, etc.).

## Detailed Design

Key decisions and their resolutions:

- ~~**Term representation**~~ — **resolved by ADR RDF-A-0002**: `Term` is an Odin tagged union over `IRI`/`Blank_Node` (`distinct string`), `Literal` (lexical, datatype, language, RDF 1.2 direction), and `^Triple` for RDF-star triple terms; value semantics, structural equality/hashing, `Graph_Label :: union { IRI, Blank_Node }` with `nil` as default graph, `Quad` embeds `Triple` via `using`. Final naming and field order are settled here.
- ~~**String ownership**~~ — **resolved by ADR RDF-A-0001**: terms are borrowed-by-default (plain slices, no ownership header) with an explicit `clone`/intern operation to promote to owned; lifetime is a documented contract, not encoded in the type. The intern-table design remains to be detailed here.
- ~~**Allocator conventions**~~ — **resolved (design session 2026-08-04)**: Odin stdlib style. Every allocating procedure (clone/intern, unescape, triple-term construction) takes a trailing `allocator := context.allocator` parameter, with mirrored `destroy` procedures. Callers wanting free-all semantics pass an arena allocator; the library never owns an arena itself.
- ~~**Equality & hashing**~~ — **resolved (design session 2026-08-04)**: overloaded proc groups so call sites read `rdf.equal(a, b)` / `rdf.hash(t)` across `Term`/`Triple`/`Quad`, implemented by per-type procedures that remain directly callable. Hash function is FNV-1a from `core:hash` — an internal detail swappable later without API change. Semantics per RDF-A-0002: structural, buffer-independent, recursing through triple terms.
- ~~**Package layout**~~ — **resolved (design session 2026-08-04)**: core `rdf` package holds the data model (terms, triples, quads, equal/hash, vocabulary constants); each format gets its own package — `rdf/triples` (N-Triples), `rdf/quads` (N-Quads), `rdf/turtle`, `rdf/trig` — importing the core relatively (`import rdf ".."`), with shared scanner internals in an internal package. The line-based format packages drop the "n" prefix by choice; the format names remain N-Triples/N-Quads in prose and docs. Layering rule: the core package must never import a format package (Odin forbids import cycles, and the model stays dependency-free for stores).

Term representation and string ownership carried lasting consequences and are captured as ADRs (RDF-A-0002, RDF-A-0001); the three conventions above are recorded here as their blast radius is local and revisiting them is cheap before implementation starts.

## Alternatives Considered

The two big representation decisions are analyzed in their ADRs: borrowed vs. owned strings in RDF-A-0001, and union vs. kind-enum vs. interned handles in RDF-A-0002. Remaining local alternatives (allocator conventions, package layout) will be recorded here as they are settled.

## Implementation Plan

1. **Discovery/design**: settle term representation, string ownership, and allocator conventions; record ADRs.
2. **Terms**: implement IRI, blank node, literal, and triple-term types with equality/hashing.
3. **Triples & quads**: composite types, equality/hashing, plus constant vocabularies.
4. **Tests & docs**: unit tests for all term kinds and memory ownership; document the public API.

Tasks will be created under this initiative once it reaches the ready phase.