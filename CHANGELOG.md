# Changelog

> [!CAUTION]
> This gem is under active development. APIs and features may change without notice.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
