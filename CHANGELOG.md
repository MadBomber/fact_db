# Changelog

> [!CAUTION]
> This gem is under active development. APIs and features may change without notice.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.3] - Unreleased

### Added

- **Output Transformers** - Transform query results into multiple formats optimized for LLM consumption
  - `RawTransformer` - Returns original ActiveRecord objects unchanged for direct database access
  - `JsonTransformer` - JSON-serializable hash format (default)
  - `TripleTransformer` - Subject-Predicate-Object triples for semantic encoding
  - `CypherTransformer` - Cypher-like graph notation with nodes and relationships
  - `TextTransformer` - Human-readable markdown format grouped by fact status
- **QueryResult** - Unified container for query results that works with all transformers
  - Normalizes facts from ActiveRecord objects or hashes
  - Resolves and caches entities referenced in facts
  - Provides iteration methods (`each_fact`, `each_entity`)
- **Temporal Query Builder** - Fluent API for point-in-time queries via `facts.at(date)`
  - Chain queries: `facts.at("2024-01-15").query("Paula's role", format: :cypher)`
  - Get facts for entity: `facts.at("2024-01-15").facts_for(entity_id)`
  - Compare dates: `facts.at("2024-01-15").compare_to("2024-06-15")`
- **Temporal Diff** - Compare what changed between two dates with `facts.diff(topic, from:, to:)`
  - Returns `:added`, `:removed`, and `:unchanged` fact arrays
- **Introspection API** - Discover what the fact database knows about
  - `facts.introspect` - Get schema, capabilities, entity types, and statistics
  - `facts.introspect("Paula Chen")` - Get coverage and relationships for a topic
  - `facts.suggest_queries(topic)` - Get suggested queries based on stored data
  - `facts.suggest_strategies(query)` - Get recommended retrieval strategies
- **Format Parameter** - All query methods now accept `format:` parameter
  - Available formats: `:raw`, `:json`, `:triples`, `:cypher`, `:text`
  - Example: `facts.query_facts(topic: "Paula", format: :cypher)`

### Changed

- `EntityService` now includes `relationship_types_for(entity_id)` and `timespan_for(entity_id)` methods
- `FactService` now includes `fact_stats(entity_id)` for per-entity statistics

## [0.0.2] - 2025-01-08

### Fixed

- Database connection now validates configuration before connecting, providing a clear `ConfigurationError: Database URL required` message instead of confusing ActiveRecord errors when `database_url` is not set
- README Getting Started examples now work correctly when copied into IRB:
  - Database URL uses `ENV['USER']` for the PostgreSQL role instead of defaulting to non-existent "postgres" role
  - Added `FactDb::Database.migrate!` step to set up the schema
  - Examples are now split into logical blocks that build on each other

## [0.0.1] - 2025-01-08

### Added

- Initial release of FactDb gem
- **Core Models**
  - `Content` - Store raw ingested content with metadata
  - `Entity` - Canonical entities with types (person, organization, etc.)
  - `EntityAlias` - Alternative names for entities
  - `Fact` - Temporal facts with `valid_at`/`invalid_at` periods
  - `EntityMention` - Link facts to entities with roles
  - `FactSource` - Audit trail linking facts to source content
- **Services**
  - `ContentService` - Ingest and manage raw content
  - `EntityService` - Create, resolve, and manage entities
  - `FactService` - Create, query, and manage temporal facts
- **Extractors**
  - `ManualExtractor` - Manual fact entry
  - `LlmExtractor` - LLM-powered fact extraction via ruby_llm
  - `RuleBasedExtractor` - Pattern-based fact extraction
- **Temporal Queries**
  - Query facts valid at a specific point in time
  - Build timelines for entities
  - Track fact validity periods
- **Entity Resolution**
  - Resolve names to canonical entities
  - Support for entity aliases
  - Batch entity resolution
- **Pipeline Processing**
  - `ExtractionPipeline` - Batch extract facts from content
  - `ResolutionPipeline` - Batch resolve entities and detect conflicts
  - Parallel processing support for large batches
- **Database**
  - PostgreSQL with pgvector extension support
  - Configurable database connection
- **Documentation**
  - GitHub Pages documentation site
  - Example programs demonstrating usage
