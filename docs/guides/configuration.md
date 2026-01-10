# Configuration

FactDb uses the `anyway_config` gem for flexible configuration via environment variables, YAML files, or Ruby code. Configuration uses **nested sections** for better organization.

## Configuration Sources

Configuration is loaded from multiple sources (lowest to highest priority):

1. **Bundled defaults** - `lib/fact_db/config/defaults.yml` (ships with gem)
2. **XDG user config** - `~/.config/fact_db/fact_db.yml`
3. **Project config** - `./config/fact_db.yml`
4. **Local overrides** - `./config/fact_db.local.yml` (gitignored)
5. **Environment variables** - `FDB_*`
6. **Ruby configure block** - `FactDb.configure { |c| ... }`

## Configuration Access Pattern

FactDb uses nested configuration sections:

```ruby
# Nested access
FactDb.config.database.url
FactDb.config.database.pool_size
FactDb.config.llm.provider
FactDb.config.llm.model
FactDb.config.ranking.ts_rank_weight
```

## Configuration Methods

### Environment Variables

All settings use the `FDB_` prefix with double underscores for nested values:

```bash
# Database settings
export FDB_DATABASE__URL="postgresql://localhost/fact_db"
export FDB_DATABASE__POOL_SIZE=10
export FDB_DATABASE__TIMEOUT=30000

# LLM settings
export FDB_LLM__PROVIDER="openai"
export FDB_LLM__MODEL="gpt-4o-mini"
export FDB_LLM__API_KEY="sk-..."

# Top-level settings
export FDB_FUZZY_MATCH_THRESHOLD=0.85
export FDB_DEFAULT_EXTRACTOR="llm"
export FDB_LOG_LEVEL="debug"
```

### YAML Configuration

Create `config/fact_db.yml` with nested sections:

```yaml
# Database
database:
  url: postgresql://localhost/fact_db
  pool_size: 10
  timeout: 30000

# Embeddings
embedding:
  dimensions: 1536

# LLM
llm:
  provider: openai
  model: gpt-4o-mini
  api_key: <%= ENV['OPENAI_API_KEY'] %>

# Ranking weights (should sum to 1.0)
ranking:
  ts_rank_weight: 0.25
  vector_similarity_weight: 0.25
  entity_mention_weight: 0.15
  direct_answer_weight: 0.15
  term_overlap_weight: 0.10
  relationship_match_weight: 0.05
  confidence_weight: 0.05

# Top-level settings
default_extractor: manual
fuzzy_match_threshold: 0.85
auto_merge_threshold: 0.95
log_level: info
```

### Ruby Block

```ruby
FactDb.configure do |config|
  # Database
  config.database.url = "postgresql://localhost/fact_db"
  config.database.pool_size = 10
  config.database.timeout = 30_000

  # Embeddings
  config.embedding.dimensions = 1536
  config.embedding_generator = ->(text) {
    # Your embedding generation logic
    OpenAI::Client.new.embeddings(input: text)
  }

  # LLM (nested access)
  config.llm.provider = :openai
  config.llm.model = "gpt-4o-mini"
  config.llm.api_key = ENV['OPENAI_API_KEY']

  # Or provide a pre-configured client
  config.llm_client = FactDb::LLM::Adapter.new(
    provider: :anthropic,
    model: "claude-sonnet-4-20250514"
  )

  # Ranking weights
  config.ranking.ts_rank_weight = 0.30
  config.ranking.vector_similarity_weight = 0.25

  # Top-level settings
  config.default_extractor = :llm
  config.fuzzy_match_threshold = 0.85
  config.auto_merge_threshold = 0.95

  # Logging
  config.logger = Rails.logger
  config.log_level = :debug
end
```

## Configuration Options

### Database Settings

Access: `FactDb.config.database.*`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | String | nil | PostgreSQL connection URL |
| `host` | String | localhost | Database host |
| `port` | Integer | 5432 | Database port |
| `name` | String | nil | Database name |
| `user` | String | nil | Database user |
| `password` | String | nil | Database password |
| `pool_size` | Integer | 5 | Connection pool size |
| `timeout` | Integer | 30000 | Query timeout in milliseconds |

### Embedding Settings

Access: `FactDb.config.embedding.*`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dimensions` | Integer | 1536 | Vector dimensions (match your model) |
| `generator` | Proc | nil | Custom embedding generation function |

### LLM Settings

Access: `FactDb.config.llm.*`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `client` | Object | nil | Pre-configured LLM client |
| `provider` | Symbol | nil | Provider name (:openai, :anthropic, etc.) |
| `model` | String | varies | Model name |
| `api_key` | String | nil | API key |

### Ranking Settings

Access: `FactDb.config.ranking.*`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ts_rank_weight` | Float | 0.25 | PostgreSQL full-text search weight |
| `vector_similarity_weight` | Float | 0.25 | Semantic similarity weight |
| `entity_mention_weight` | Float | 0.15 | Entity mentions weight |
| `direct_answer_weight` | Float | 0.15 | Direct answer pattern weight |
| `term_overlap_weight` | Float | 0.10 | Query word matches weight |
| `relationship_match_weight` | Float | 0.05 | Relationship words weight |
| `confidence_weight` | Float | 0.05 | Stored confidence score weight |

**Note:** Weights should sum to approximately 1.0.

### Top-Level Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_extractor` | Symbol | :manual | Default extraction method |
| `fuzzy_match_threshold` | Float | 0.85 | Minimum similarity for fuzzy matching |
| `auto_merge_threshold` | Float | 0.95 | Similarity threshold for auto-merge |
| `log_level` | Symbol | :info | Log level |

## LLM Provider Configuration

### OpenAI

```ruby
FactDb.configure do |config|
  config.llm.provider = :openai
  config.llm.model = "gpt-4o-mini"  # or "gpt-4o", "gpt-4-turbo"
  config.llm.api_key = ENV['OPENAI_API_KEY']
end
```

### Anthropic

```ruby
FactDb.configure do |config|
  config.llm.provider = :anthropic
  config.llm.model = "claude-sonnet-4-20250514"
  config.llm.api_key = ENV['ANTHROPIC_API_KEY']
end
```

### Google Gemini

```ruby
FactDb.configure do |config|
  config.llm.provider = :gemini
  config.llm.model = "gemini-2.0-flash"
  config.llm.api_key = ENV['GEMINI_API_KEY']
end
```

### Ollama (Local)

```ruby
FactDb.configure do |config|
  config.llm.provider = :ollama
  config.llm.model = "llama3.2"
  # No API key needed for local Ollama
end
```

### AWS Bedrock

```ruby
FactDb.configure do |config|
  config.llm.provider = :bedrock
  config.llm.model = "claude-sonnet-4"
  # Uses AWS credentials from environment
end
```

### OpenRouter

```ruby
FactDb.configure do |config|
  config.llm.provider = :openrouter
  config.llm.model = "anthropic/claude-sonnet-4"
  config.llm.api_key = ENV['OPENROUTER_API_KEY']
end
```

## XDG User Configuration

FactDb supports XDG Base Directory Specification for user-level configuration:

- `~/.config/fact_db/fact_db.yml` (Linux/macOS)
- `~/Library/Application Support/fact_db/fact_db.yml` (macOS)
- `$XDG_CONFIG_HOME/fact_db/fact_db.yml` (if XDG_CONFIG_HOME is set)

This allows you to set personal defaults that apply across all projects.

## Environment-Specific Configuration

The bundled defaults support environment-specific overrides:

```yaml
# config/fact_db.yml
defaults:
  embedding:
    dimensions: 1536
  fuzzy_match_threshold: 0.85

development:
  database:
    name: fact_db_development
  log_level: debug

test:
  database:
    name: fact_db_test
  log_level: warn

production:
  database:
    pool_size: 25
  log_level: info
```

Environment is detected from: `FDB_ENV` > `RAILS_ENV` > `RACK_ENV` > `'development'`

## Validation

Validate configuration at startup:

```ruby
FactDb.configure do |config|
  config.database.url = ENV['DATABASE_URL']
end

# Raises ConfigurationError if invalid
FactDb.config.validate!
```

## Reset Configuration

For testing, reset configuration between tests:

```ruby
# In test setup
FactDb.reset_configuration!
```

## Environment Helpers

```ruby
FactDb.config.test?        # true if FDB_ENV == 'test'
FactDb.config.development? # true if FDB_ENV == 'development'
FactDb.config.production?  # true if FDB_ENV == 'production'
FactDb.config.environment  # returns current environment string
```
