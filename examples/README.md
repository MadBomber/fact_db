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
