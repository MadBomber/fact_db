# LLM Integration

FactDb integrates with multiple LLM providers via the `ruby_llm` gem for AI-powered fact extraction.

## Setup

### Install ruby_llm

Add to your Gemfile:

```ruby
gem 'ruby_llm'
```

### Configure Provider

=== "OpenAI"

    ```ruby
    FactDb.configure do |config|
      config.llm.provider = :openai
      config.llm.model = "gpt-4o-mini"
      config.llm.api_key = ENV['OPENAI_API_KEY']
    end
    ```

=== "Anthropic"

    ```ruby
    FactDb.configure do |config|
      config.llm.provider = :anthropic
      config.llm.model = "claude-sonnet-4-20250514"
      config.llm.api_key = ENV['ANTHROPIC_API_KEY']
    end
    ```

=== "Google Gemini"

    ```ruby
    FactDb.configure do |config|
      config.llm.provider = :gemini
      config.llm.model = "gemini-2.0-flash"
      config.llm.api_key = ENV['GEMINI_API_KEY']
    end
    ```

=== "Ollama (Local)"

    ```ruby
    FactDb.configure do |config|
      config.llm.provider = :ollama
      config.llm.model = "llama3.2"
    end
    ```

=== "Environment Variables"

    ```bash
    export FDB_LLM__PROVIDER=openai
    export FDB_LLM__MODEL=gpt-4o-mini
    export FDB_LLM__API_KEY=sk-...
    ```

## Supported Providers

| Provider | Models | Config Key |
|----------|--------|------------|
| OpenAI | gpt-4o, gpt-4o-mini, gpt-4-turbo | `OPENAI_API_KEY` |
| Anthropic | claude-sonnet-4, claude-3-haiku | `ANTHROPIC_API_KEY` |
| Google Gemini | gemini-2.0-flash, gemini-pro | `GEMINI_API_KEY` |
| Ollama | llama3.2, mistral, codellama | (local) |
| AWS Bedrock | claude-sonnet-4, titan | AWS credentials |
| OpenRouter | Various | `OPENROUTER_API_KEY` |

## Default Models

If no model is specified, these defaults are used:

```ruby
PROVIDER_DEFAULTS = {
  openai: "gpt-4o-mini",
  anthropic: "claude-sonnet-4-20250514",
  gemini: "gemini-2.0-flash",
  ollama: "llama3.2",
  bedrock: "claude-sonnet-4",
  openrouter: "anthropic/claude-sonnet-4"
}
```

## Using LLM Extraction

```ruby
facts = FactDb.new

# Ingest content
content = facts.ingest(
  "Paula Chen joined Microsoft as Principal Engineer on January 10, 2024. She previously worked at Google for 5 years.",
  type: :announcement
)

# Extract facts using LLM
extracted = facts.extract_facts(content.id, extractor: :llm)

extracted.each do |fact|
  puts "Fact: #{fact.fact_text}"
  puts "  Valid: #{fact.valid_at}"
  puts "  Confidence: #{fact.confidence}"
  fact.entity_mentions.each do |m|
    puts "  Entity: #{m.entity.canonical_name} (#{m.mention_role})"
  end
end
```

## Extraction Prompts

The LLM extractor uses carefully designed prompts to extract:

1. **Facts** - Temporal assertions about entities
2. **Entities** - People, organizations, places mentioned
3. **Dates** - When facts became valid
4. **Relationships** - How entities relate to facts

### Example Prompt Structure

```
Extract temporal facts from this content. For each fact:
1. Identify the assertion (what is being stated)
2. Identify entities mentioned (people, organizations, places)
3. Determine when the fact became valid
4. Assess confidence level

Content:
{content.raw_text}

Return JSON:
{
  "facts": [
    {
      "text": "...",
      "valid_at": "YYYY-MM-DD",
      "entities": [
        {"name": "...", "type": "person|organization|place", "role": "subject|object|..."}
      ],
      "confidence": 0.0-1.0
    }
  ]
}
```

## Custom LLM Client

Provide a pre-configured client:

```ruby
# Create custom adapter
adapter = FactDb::LLM::Adapter.new(
  provider: :openai,
  model: "gpt-4o",
  api_key: ENV['OPENAI_API_KEY']
)

FactDb.configure do |config|
  config.llm_client = adapter
end
```

## Direct LLM Usage

Use the adapter directly:

```ruby
adapter = FactDb::LLM::Adapter.new(
  provider: :anthropic,
  model: "claude-sonnet-4-20250514"
)

response = adapter.chat("Extract facts from: Paula joined Microsoft on Jan 10, 2024")
puts response
```

## Error Handling

```ruby
begin
  extracted = facts.extract_facts(content.id, extractor: :llm)
rescue FactDb::ConfigurationError => e
  # LLM not configured or ruby_llm missing
  puts "LLM Error: #{e.message}"
  # Fall back to rule-based
  extracted = facts.extract_facts(content.id, extractor: :rule_based)
rescue StandardError => e
  # API error, rate limit, etc.
  puts "Extraction failed: #{e.message}"
end
```

## Batch Processing with LLM

Process multiple documents efficiently:

```ruby
content_ids = [content1.id, content2.id, content3.id]

# Parallel processing (uses simple_flow pipeline)
results = facts.batch_extract(content_ids, extractor: :llm, parallel: true)

results.each do |result|
  if result[:error]
    puts "Error for #{result[:content_id]}: #{result[:error]}"
  else
    puts "Extracted #{result[:facts].count} facts from #{result[:content_id]}"
  end
end
```

## Cost Optimization

### Use Appropriate Models

```ruby
# For simple extractions, use smaller models
config.llm.model = "gpt-4o-mini"  # Cheaper than gpt-4o

# For complex documents, use larger models
config.llm.model = "gpt-4o"
```

### Batch Processing

```ruby
# Process in batches to reduce API calls
content_ids.each_slice(10) do |batch|
  facts.batch_extract(batch, extractor: :llm)
  sleep(1)  # Rate limiting
end
```

### Local Models

```ruby
# Use Ollama for development/testing
FactDb.configure do |config|
  config.llm.provider = :ollama
  config.llm.model = "llama3.2"
end
```

## Testing

Mock LLM responses in tests:

```ruby
class MockLLMClient
  def chat(prompt)
    # Return predictable test data
    '{"facts": [{"text": "Test fact", "valid_at": "2024-01-01", "entities": [], "confidence": 0.9}]}'
  end
end

FactDb.configure do |config|
  config.llm_client = MockLLMClient.new
end
```

## Best Practices

### 1. Validate Extractions

```ruby
extracted = facts.extract_facts(content.id, extractor: :llm)

extracted.each do |fact|
  # Flag low-confidence extractions
  if fact.confidence < 0.7
    fact.update!(metadata: { needs_review: true })
  end
end
```

### 2. Use Caching

```ruby
# Cache LLM responses for repeated content
cache_key = "llm_extraction:#{content.content_hash}"
extracted = Rails.cache.fetch(cache_key) do
  facts.extract_facts(content.id, extractor: :llm)
end
```

### 3. Handle Rate Limits

```ruby
require 'retryable'

Retryable.retryable(tries: 3, sleep: 5) do
  facts.extract_facts(content.id, extractor: :llm)
end
```

### 4. Monitor Usage

```ruby
# Track extraction statistics
extracted = facts.extract_facts(content.id, extractor: :llm)
StatsD.increment('fact_db.llm_extractions')
StatsD.histogram('fact_db.facts_per_content', extracted.count)
```
