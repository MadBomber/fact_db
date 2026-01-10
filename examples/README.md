# FactDb Examples

This directory contains demonstration programs showcasing the capabilities of the FactDb gem.

## Prerequisites

1. PostgreSQL database with pgvector extension
2. Set the `DATABASE_URL` environment variable or use the default `postgres://localhost/fact_db_demo`
3. Run migrations to set up the schema

```bash
bundle install
DATABASE_URL=postgres://localhost/fact_db_demo rake db:migrate
```

## Examples

### basic_usage.rb

**Foundational introduction to FactDb**

Demonstrates:
- Configuring FactDb
- Ingesting content (emails, documents)
- Creating entities (people, organizations)
- Creating facts with entity mentions
- Basic fact queries
- Getting system statistics

```bash
ruby examples/basic_usage.rb
```

### entity_management.rb

**Deep dive into entity operations**

Demonstrates:
- Creating entities with multiple types (person, organization, place)
- Managing aliases (names, emails, abbreviations)
- Entity resolution using fuzzy matching
- Merging duplicate entities
- Searching entities by name and type
- Building entity timelines

```bash
ruby examples/entity_management.rb
```

### temporal_queries.rb

**Working with time-based data**

Demonstrates:
- Creating facts with temporal bounds (valid_at, invalid_at)
- Point-in-time queries ("What was true on date X?")
- Distinguishing current vs historical facts
- Superseding facts (replacing old information with new)
- Building temporal timelines
- Computing diffs between time periods
- Querying facts by entity role

```bash
ruby examples/temporal_queries.rb
```

### rule_based_extraction.rb

**Automatic fact extraction from text**

Demonstrates:
- Using the rule-based extractor
- Pattern detection for employment, relationships, locations
- Processing extraction results
- Saving extracted facts to the database
- Entity auto-creation from extracted text
- Testing individual extraction patterns

```bash
ruby examples/rule_based_extraction.rb
```

### hr_system.rb

**Practical HR knowledge management system**

A comprehensive real-world example demonstrating:
- Organizational hierarchy (company, departments, locations)
- Employee profile management
- Recording employment history
- Processing promotions with fact supersession
- Recording employee transfers
- Historical queries ("What was X's role in 2024?")
- Organization chart queries
- Complete audit trails with source documents
- HR statistics and reporting

```bash
ruby examples/hr_system.rb
```

### output_formats.rb

**LLM-optimized output transformers**

Demonstrates the new output format system:
- JSON format (default) for structured data
- Triples format (Subject-Predicate-Object) for knowledge graphs
- Cypher format for graph database notation
- Text format for human-readable output
- Raw format for ActiveRecord access
- Using formats with queries

```bash
ruby examples/output_formats.rb
```

### fluent_temporal_api.rb

**Fluent query builder for temporal analysis**

Demonstrates the new chainable API:
- `facts.at(date)` - Query at a specific point in time
- `facts.at(date).facts_for(entity_id)` - Entity state at a date
- `facts.at(date).compare_to(other_date)` - Compare two dates
- `facts.diff(topic, from:, to:)` - Compute temporal diffs
- Career timeline snapshots across multiple dates

```bash
ruby examples/fluent_temporal_api.rb
```

### introspection.rb

**Schema and data introspection**

Demonstrates discovery capabilities:
- `facts.introspect()` - Discover system capabilities
- `facts.introspect(topic)` - Examine specific entities
- `facts.suggest_queries(topic)` - Get query suggestions
- `facts.suggest_strategies(query)` - Strategy recommendations
- `entity_service.relationship_types` - All relationship types
- `entity_service.timespan_for(id)` - Fact date range
- `fact_service.fact_stats(id)` - Fact status breakdown
- Building LLM context with introspection

```bash
ruby examples/introspection.rb
```

### query_context.rb

**Natural language query to context generation**

Takes a natural language query and generates context from the facts database suitable for LLM consumption. Features multi-signal relevance ranking with configurable weights.

Demonstrates:
- Extracting entity candidates from natural language queries
- Resolving entities from query text (proper nouns, possessives)
- Multi-strategy fact gathering (entity mentions, full-text search, semantic search)
- **Multi-signal relevance ranking** with PostgreSQL ts_rank, pgvector similarity, and heuristics
- Generating context in multiple output formats
- Building LLM-ready context from a facts database

```bash
# Basic usage
ruby examples/query_context.rb "Who is Sapphira's husband?"

# With verbose output showing processing steps and signal breakdown
ruby examples/query_context.rb --verbose "What happened to Ananias?"

# Different output formats
ruby examples/query_context.rb --format triples "Tell me about Peter"
ruby examples/query_context.rb --format json "Who are the apostles?"
ruby examples/query_context.rb --format cypher "Where was Stephen martyred?"

# Disable ranking (return facts in database order)
ruby examples/query_context.rb --no-rank "Tell me about the apostles"
```

**Ranking Signals** (configurable via FactDb.config.ranking):
| Signal | Default Weight | Description |
|--------|----------------|-------------|
| ts_rank | 0.25 | PostgreSQL full-text search relevance |
| vector_similarity | 0.25 | Semantic similarity via pgvector embeddings |
| entity_mentions | 0.15 | Facts mentioning query entities |
| direct_answer | 0.15 | Pattern match for query intent |
| term_overlap | 0.10 | Query word matches |
| relationship_match | 0.05 | Relationship words (husband, wife, etc.) |
| confidence | 0.05 | Fact's stored confidence score |

**Note:** Run `ingest_demo.rb acts_esv/` first to populate the database with biblical facts.

## Key Concepts

### The Event Clock Pattern

FactDb implements the Event Clock concept where:
- Every fact has a `valid_at` timestamp (when it became true)
- Facts may have an `invalid_at` timestamp (when they stopped being true)
- This enables temporal queries at any point in time

### Entity Resolution

Entities can have multiple aliases and are resolved using fuzzy matching:
- "Bob Johnson" and "Robert Johnson" can resolve to the same entity
- Duplicates can be merged while preserving audit history

### Fact Lifecycle

Facts progress through states:
- `canonical` - Currently accepted as true
- `superseded` - Replaced by a newer fact
- `corroborated` - Supported by other evidence
- `synthesized` - Derived from multiple sources

### Source Tracking

All facts link back to source content:
- Primary sources (direct evidence)
- Supporting sources (additional evidence)
- Corroborating sources (independent confirmation)

### Output Formats

Facts can be transformed into multiple formats optimized for different consumers:
- `json` - Structured data with entities and metadata
- `triples` - Subject-Predicate-Object for semantic reasoning
- `cypher` - Graph notation for Neo4j-style visualization
- `text` - Human-readable markdown format
- `raw` - Direct ActiveRecord objects

### Fluent Temporal API

The chainable `at()` method provides an intuitive way to query temporal data:
```ruby
facts.at("2024-01-15").facts_for(entity_id)          # What did we know?
facts.at("2024-01-15").compare_to("2024-06-15")      # What changed?
facts.diff(nil, from: "2024-01", to: "2024-06")      # Detailed diff
```

### Introspection

Discover what the system knows before querying:
```ruby
facts.introspect              # Schema, capabilities, statistics
facts.introspect("Paula")     # Entity coverage, relationships
facts.suggest_queries("Paula") # What can I ask about Paula?
```

### Ranking Configuration

Tune relevance ranking weights for your use case:
```ruby
FactDb.configure do |config|
  # Boost semantic search for concept-heavy domains
  config.ranking.vector_similarity_weight = 0.35
  config.ranking.ts_rank_weight = 0.15

  # Or boost entity mentions for person-centric queries
  config.ranking.entity_mention_weight = 0.30
end
```

Or via environment variables:
```bash
export FDB_RANKING__VECTOR_SIMILARITY_WEIGHT=0.35
export FDB_RANKING__TS_RANK_WEIGHT=0.15
```
