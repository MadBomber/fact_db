# API Reference

Complete API documentation for FactDb.

## Main Classes

- [Facts](facts.md) - Main interface for FactDb operations

## Models

- [Source](models/source.md) - Immutable source content
- [Entity](models/entity.md) - Resolved identities
- [Fact](models/fact.md) - Temporal assertions

## Services

- [SourceService](services/source-service.md) - Ingest and manage sources
- [EntityService](services/entity-service.md) - Create and resolve entities
- [FactService](services/fact-service.md) - Extract and query facts

## Extractors

- [ManualExtractor](extractors/manual.md) - API-driven extraction
- [LLMExtractor](extractors/llm.md) - AI-powered extraction
- [RuleBasedExtractor](extractors/rule-based.md) - Pattern matching

## Pipeline

- [ExtractionPipeline](pipeline/extraction.md) - Concurrent extraction
- [ResolutionPipeline](pipeline/resolution.md) - Parallel resolution

## Module Structure

```
FactDb
├── Facts                    # Main class
├── Config                   # Configuration
├── Database                 # Database connection
├── Models
│   ├── Source
│   ├── Entity
│   ├── EntityAlias
│   ├── Fact
│   ├── EntityMention
│   └── FactSource
├── Services
│   ├── SourceService
│   ├── EntityService
│   └── FactService
├── Extractors
│   ├── Base
│   ├── ManualExtractor
│   ├── LLMExtractor
│   └── RuleBasedExtractor
├── Resolution
│   ├── EntityResolver
│   └── FactResolver
├── Pipeline
│   ├── ExtractionPipeline
│   └── ResolutionPipeline
├── Temporal
│   ├── Query
│   └── Timeline
└── LLM
    └── Adapter
```
