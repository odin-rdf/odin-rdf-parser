---
id: odin-rdf-parser
level: vision
title: "odin-rdf-parser"
short_code: "RDF-V-0001"
created_at: 2026-08-04T09:24:04.787158+00:00
updated_at: 2026-08-06T12:00:00.000000+00:00
archived: false

tags:
  - "#vision"
  - "#phase/published"


exit_criteria_met: true
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

**Every success criterion is met (2026-08-06).** The data model (RDF-I-0001) and parsers/emitters for all four formats (RDF-I-0002, RDF-I-0003) are complete, passing all 1045 tests across the 10 vendored W3C suites, including RDF-star, with steady-state-zero-allocation parsing verified by benchmarks. The finish-up backlog is done: the large-document streaming contract is decided and documented (RDF-T-0024: whole-document buffer, mmap for large files), the public API carries full contract documentation (RDF-T-0023), and the repo has a README with compile-verified examples (RDF-T-0022).

The last criterion — downstream validation — closed twice over: **odin-rdf-store** ingests all four formats through these parsers under the clone/intern discipline of RDF-A-0001, and **odin-rdf-sparql** emits through these emitters and consumes this data model as its term vocabulary. The library is no longer being validated by its own tests alone.

Since then: CI runs the four suites plus a `-vet -strict-style` pass on Linux, macOS, and Windows; the first Windows run found that the vendored W3C fixtures were being corrupted by line-ending translation on checkout (six eval tests, literals whose value is a raw line feed), fixed by `.gitattributes` — a portability bug that had been latent for as long as the suite ran on one platform. Tagged **v0.1.0**.

Open work is elective rather than remedial. RDF/XML and JSON-LD remain out of scope by decision; the one consequence downstream is that ten `sparql11-subquery` entries in odin-rdf-sparql's corpus can never run, accepted and documented there as a ceiling. The family's open **term-identity** question — whether language tags fold case and IRIs normalize — would land partly here if the answer puts normalization in the data model, and would change this package's documented "stored as given; no normalization" contract.

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
- **Streaming-friendly**: Parsing and emitting are statement-at-a-time and never materialize the graph; parser memory is bounded by nesting depth and the prefix map, not document size. The document text itself lives in a caller-owned buffer — whole-document-in-buffer is the input contract, with memory-mapping as the intended path for large files (decided in RDF-T-0024).
- **Test-suite driven**: Use the official W3C test suites as the primary measure of correctness.

## Constraints

- Written in the Odin programming language with no external library dependencies.
- Scope is limited to parsing and emitting the four named formats plus the core data model; triple stores, SPARQL engines, and other consumers are explicitly out of scope for this project (they build on it).
- Other RDF serializations (RDF/XML, JSON-LD) are out of scope for now.