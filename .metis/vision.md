---
id: odin-rdf-parser
level: vision
title: "odin-rdf-parser"
short_code: "RDF-V-0001"
created_at: 2026-08-04T09:24:04.787158+00:00
updated_at: 2026-08-04T09:28:54.622787+00:00
archived: false

tags:
  - "#vision"
  - "#phase/published"


exit_criteria_met: false
initiative_id: NULL
---

# odin-rdf-parser Vision

## Purpose

Provide the Odin programming language with a solid, standards-compliant foundation for working with RDF data. This project implements parsers and emitters for the core RDF serialization formats — N-Triples, Turtle, N-Quads, and TriG — so that Odin developers can read, write, and process RDF graphs and datasets natively, without bindings to external libraries.

## Product/Solution Overview

odin-rdf-parser is a library (not an application) targeting Odin developers who build RDF-based systems. It offers:

- **Parsers** that turn N-Triples, Turtle, N-Quads, and TriG documents into streams or collections of triples/quads.
- **Emitters** that serialize triples/quads back into each of the four formats.
- **Core RDF primitives** — IRIs, blank nodes, literals (with datatypes and language tags), triples, and quads — designed as reusable building blocks.
- **RDF-star support** across the data model and all four formats, so triples can themselves be used as terms (quoted/embedded triples) per RDF 1.2.

The library is deliberately low-level: it supplies the primitives on which higher-level infrastructure such as triple/quad stores, SPARQL query engines, reasoners, and linked-data tooling can be built.

## Current State

The project is at its inception. No parsing or emitting functionality exists yet. Odin has no established RDF ecosystem, so this library starts from a clean slate with no legacy constraints.

## Future State

A complete, well-tested Odin library where:

- All four serialization formats (N-Triples, Turtle, N-Quads, TriG) can be parsed and emitted with full conformance to their W3C specifications.
- The core term/triple/quad data model is stable and ergonomic enough to serve as the common vocabulary for downstream projects.
- Downstream projects (triple/quad stores, SPARQL engines) can depend on this library as their ingestion and serialization layer.

## Major Features

- **N-Triples parser & emitter**: The simplest line-based triple format; foundation for the other grammars and for W3C test-suite tooling.
- **Turtle parser & emitter**: The most widely used human-readable RDF format, including prefixes, base IRIs, lists, and abbreviated syntax.
- **N-Quads parser & emitter**: Line-based quad format extending N-Triples with a graph label, enabling dataset-level processing.
- **TriG parser & emitter**: Turtle extended with named graph blocks for serializing full RDF datasets.
- **RDF data model primitives**: Shared types for IRIs, blank nodes, literals, triples, and quads used consistently across all parsers and emitters.
- **RDF-star (RDF 1.2)**: Triple terms supported in the data model and in the star variants of all four syntaxes (N-Triples-star, Turtle-star, N-Quads-star, TriG-star).

## Success Criteria

- Parsers and emitters for all four formats pass the relevant W3C RDF test suites, including the RDF-star test cases.
- Round-tripping (parse → emit → parse) preserves data semantics in every format.
- The library's primitives are used successfully as the foundation for at least one downstream project (e.g., a triple/quad store or SPARQL engine prototype).
- The public API is documented and idiomatic Odin.

## Principles

- **Standards first**: Conformance to the W3C RDF 1.1/1.2 specifications takes precedence over convenience shortcuts.
- **Primitives over frameworks**: Provide small, composable building blocks; leave policy and higher-level abstractions to downstream projects.
- **Idiomatic Odin**: Embrace Odin conventions — explicit memory management, allocator awareness, and straightforward procedural APIs.
- **Streaming-friendly**: Parsing and emitting should be usable on large documents without requiring the whole graph in memory.
- **Test-suite driven**: Use the official W3C test suites as the primary measure of correctness.

## Constraints

- Written in the Odin programming language with no external library dependencies.
- Scope is limited to parsing and emitting the four named formats plus the core data model; triple stores, SPARQL engines, and other consumers are explicitly out of scope for this project (they build on it).
- Other RDF serializations (RDF/XML, JSON-LD) are out of scope for now.