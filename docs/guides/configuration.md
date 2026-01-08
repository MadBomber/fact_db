# Configuration

FactDb uses the `anyway_config` gem for flexible configuration via environment variables, YAML files, or Ruby code.

## Configuration Methods

### Environment Variables

All settings can be configured via environment variables with the `EVENT_CLOCK_` prefix:

```bash
export EVENT_CLOCK_DATABASE_URL="postgresql://localhost/fact_db"
export EVENT_CLOCK_DATABASE_POOL_SIZE=10
export EVENT_CLOCK_LLM_PROVIDER="openai"
export EVENT_CLOCK_LLM_MODEL="gpt-4o-mini"
export EVENT_CLOCK_LLM_API_KEY="sk-..."
export EVENT_CLOCK_FUZZY_MATCH_THRESHOLD=0.85
```

### YAML Configuration

Create `config/fact_db.yml`:

```yaml
# Database
database_url: postgresql://localhost/fact_db
database_pool_size: 10
database_timeout: 30000

# Embeddings
embedding_dimensions: 1536

# LLM
llm_provider: openai
llm_model: gpt-4o-mini
llm_api_key: <%= ENV['OPENAI_API_KEY'] %>

# Extraction
default_extractor: manual

# Entity Resolution
fuzzy_match_threshold: 0.85
auto_merge_threshold: 0.95

# Logging
log_level: info
```

### Ruby Block

```ruby
FactDb.configure do |config|
  # Database
  config.database_url = "postgresql://localhost/fact_db"
  config.database_pool_size = 10
  config.database_timeout = 30_000

  # Embeddings
  config.embedding_dimensions = 1536
  config.embedding_generator = ->(text) {
    # Your embedding generation logic
    OpenAI::Client.new.embeddings(input: text)
  }

  # LLM
  config.llm_provider = :openai
  config.llm_model = "gpt-4o-mini"
  config.llm_api_key = ENV['OPENAI_API_KEY']

  # Or provide a pre-configured client
  config.llm_client = FactDb::LLM::Adapter.new(
    provider: :anthropic,
    model: "claude-sonnet-4-20250514"
  )

  # Extraction
  config.default_extractor = :llm

  # Entity Resolution
  config.fuzzy_match_threshold = 0.85
  config.auto_merge_threshold = 0.95

  # Logging
  config.logger = Rails.logger
  config.log_level = :debug
end
```

## Configuration Options

### Database Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `database_url` | String | nil | PostgreSQL connection URL (required) |
| `database_pool_size` | Integer | 5 | Connection pool size |
| `database_timeout` | Integer | 30000 | Query timeout in milliseconds |

### Embedding Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `embedding_dimensions` | Integer | 1536 | Vector dimensions (match your model) |
| `embedding_generator` | Proc | nil | Custom embedding generation function |

### LLM Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `llm_client` | Object | nil | Pre-configured LLM client |
| `llm_provider` | Symbol | nil | Provider name (:openai, :anthropic, etc.) |
| `llm_model` | String | varies | Model name |
| `llm_api_key` | String | nil | API key |

### Extraction Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_extractor` | Symbol | :manual | Default extraction method |

### Resolution Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `fuzzy_match_threshold` | Float | 0.85 | Minimum similarity for fuzzy matching |
| `auto_merge_threshold` | Float | 0.95 | Similarity threshold for auto-merge |

### Logging Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `logger` | Logger | STDOUT | Logger instance |
| `log_level` | Symbol | :info | Log level |

## LLM Provider Configuration

### OpenAI

```ruby
FactDb.configure do |config|
  config.llm_provider = :openai
  config.llm_model = "gpt-4o-mini"  # or "gpt-4o", "gpt-4-turbo"
  config.llm_api_key = ENV['OPENAI_API_KEY']
end
```

### Anthropic

```ruby
FactDb.configure do |config|
  config.llm_provider = :anthropic
  config.llm_model = "claude-sonnet-4-20250514"
  config.llm_api_key = ENV['ANTHROPIC_API_KEY']
end
```

### Google Gemini

```ruby
FactDb.configure do |config|
  config.llm_provider = :gemini
  config.llm_model = "gemini-2.0-flash"
  config.llm_api_key = ENV['GEMINI_API_KEY']
end
```

### Ollama (Local)

```ruby
FactDb.configure do |config|
  config.llm_provider = :ollama
  config.llm_model = "llama3.2"
  # No API key needed for local Ollama
end
```

### AWS Bedrock

```ruby
FactDb.configure do |config|
  config.llm_provider = :bedrock
  config.llm_model = "claude-sonnet-4"
  # Uses AWS credentials from environment
end
```

### OpenRouter

```ruby
FactDb.configure do |config|
  config.llm_provider = :openrouter
  config.llm_model = "anthropic/claude-sonnet-4"
  config.llm_api_key = ENV['OPENROUTER_API_KEY']
end
```

## Environment-Specific Configuration

Use YAML anchors for shared settings:

```yaml
# config/fact_db.yml
defaults: &defaults
  embedding_dimensions: 1536
  fuzzy_match_threshold: 0.85

development:
  <<: *defaults
  database_url: postgresql://localhost/fact_db_dev
  log_level: debug

test:
  <<: *defaults
  database_url: postgresql://localhost/fact_db_test
  log_level: warn

production:
  <<: *defaults
  database_url: <%= ENV['DATABASE_URL'] %>
  log_level: info
```

## Validation

Validate configuration at startup:

```ruby
FactDb.configure do |config|
  config.database_url = ENV['DATABASE_URL']
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
