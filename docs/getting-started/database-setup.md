# Database Setup

FactDb uses PostgreSQL with the pgvector extension for storing content, entities, and facts with semantic search capabilities.

## Create Database

```bash
createdb fact_db
```

## Enable pgvector

Connect to your database and enable the extension:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

## Run Migrations

FactDb provides migrations that create all necessary tables:

```ruby
require 'fact_db'

FactDb.configure do |config|
  config.database.url = "postgresql://localhost/fact_db"
end

FactDb::Database.migrate!
```

## Schema Overview

The migrations create six tables:

### contents

Stores immutable source documents.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| content_hash | string | SHA256 hash for deduplication |
| content_type | string | Type (email, document, article) |
| raw_text | text | Original content |
| title | string | Optional title |
| source_uri | string | Original location |
| source_metadata | jsonb | Additional metadata |
| embedding | vector(1536) | Semantic search vector |
| captured_at | timestamptz | When content was captured |

### entities

Stores resolved identities.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| canonical_name | string | Authoritative name |
| entity_type | string | person, organization, place, etc. |
| resolution_status | string | unresolved, resolved, merged |
| merged_into_id | bigint | Points to canonical entity if merged |
| metadata | jsonb | Additional attributes |
| embedding | vector(1536) | Semantic search vector |

### entity_aliases

Stores alternative names for entities.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| entity_id | bigint | Foreign key to entities |
| alias_text | string | Alternative name |
| alias_type | string | nickname, abbreviation, etc. |
| confidence | float | Match confidence (0-1) |

### facts

Stores temporal assertions.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| fact_text | text | The assertion |
| fact_hash | string | For deduplication |
| valid_at | timestamptz | When fact became true |
| invalid_at | timestamptz | When fact stopped being true |
| status | string | canonical, superseded, corroborated, synthesized |
| superseded_by_id | bigint | Points to replacing fact |
| derived_from_ids | bigint[] | Source facts for synthesized |
| corroborated_by_ids | bigint[] | Corroborating facts |
| confidence | float | Extraction confidence |
| extraction_method | string | manual, llm, rule_based |
| metadata | jsonb | Additional data |
| embedding | vector(1536) | Semantic search vector |

### entity_mentions

Links facts to entities.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| fact_id | bigint | Foreign key to facts |
| entity_id | bigint | Foreign key to entities |
| mention_text | string | Text that mentioned entity |
| mention_role | string | subject, object, location, etc. |
| confidence | float | Resolution confidence |

### fact_sources

Links facts to source content.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| fact_id | bigint | Foreign key to facts |
| content_id | bigint | Foreign key to contents |
| source_type | string | primary, supporting, contradicting |
| excerpt | text | Relevant text excerpt |
| confidence | float | Source confidence |

## Indexes

The migrations create indexes for:

- Content hash (unique)
- Content type
- Full-text search on raw_text
- Entity canonical name
- Entity type
- Fact status
- Temporal range queries (valid_at, invalid_at)
- HNSW indexes for vector similarity search

## Custom Migration

If you need to integrate with an existing database or customize the schema:

```ruby
# Copy migration files to your project
FileUtils.cp_r(
  FactDb.root.join('db/migrate'),
  Rails.root.join('db/migrate')
)

# Or run standalone
FactDb::Database.migrate!(
  migrations_path: '/custom/path/to/migrations'
)
```

## Connection Pool

Configure the connection pool for your workload:

```ruby
FactDb.configure do |config|
  config.database.url = ENV['DATABASE_URL']
  config.database.pool_size = 10  # Default: 5
  config.database.timeout = 60_000  # Default: 30000ms
end
```

Or via environment variables:

```bash
export FDB_DATABASE__URL="postgresql://localhost/fact_db"
export FDB_DATABASE__POOL_SIZE=10
export FDB_DATABASE__TIMEOUT=60000
```

## Next Steps

- [Quick Start](quick-start.md) - Start using FactDb
- [Configuration](../guides/configuration.md) - Full configuration options
