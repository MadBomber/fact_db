# LLMExtractor

AI-powered fact extraction using large language models.

## Class: `FactDb::Extractors::LLMExtractor`

```ruby
extractor = FactDb::Extractors::LLMExtractor.new(config)
```

## Requirements

- `ruby_llm` gem installed
- LLM provider configured (API key, model)

## Configuration

```ruby
FactDb.configure do |config|
  config.llm_provider = :openai
  config.llm_model = "gpt-4o-mini"
  config.llm_api_key = ENV['OPENAI_API_KEY']
end
```

## Methods

### extract

```ruby
def extract(content)
```

Extract facts from content using LLM.

**Parameters:**

- `content` (Models::Content) - Content to process

**Returns:** `Array<Models::Fact>`

**Example:**

```ruby
extractor = LLMExtractor.new(config)
facts = extractor.extract(content)

facts.each do |fact|
  puts fact.fact_text
  puts "  Valid: #{fact.valid_at}"
  puts "  Confidence: #{fact.confidence}"
end
```

## Extraction Process

1. **Prompt Construction** - Build prompt with content text
2. **LLM Call** - Send to configured LLM provider
3. **Response Parsing** - Parse JSON response
4. **Fact Creation** - Create fact records
5. **Entity Resolution** - Resolve mentioned entities
6. **Source Linking** - Link facts to source content

## Prompt Structure

The extractor uses a structured prompt:

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

## Supported Providers

| Provider | Models | Config |
|----------|--------|--------|
| OpenAI | gpt-4o, gpt-4o-mini | `llm_provider: :openai` |
| Anthropic | claude-sonnet-4, claude-3-haiku | `llm_provider: :anthropic` |
| Google | gemini-2.0-flash | `llm_provider: :gemini` |
| Ollama | llama3.2, mistral | `llm_provider: :ollama` |
| AWS Bedrock | claude-sonnet-4 | `llm_provider: :bedrock` |
| OpenRouter | Various | `llm_provider: :openrouter` |

## Error Handling

```ruby
begin
  facts = extractor.extract(content)
rescue FactDb::ConfigurationError => e
  # LLM not configured
  puts "Config error: #{e.message}"
rescue FactDb::ExtractionError => e
  # Extraction failed
  puts "Extraction error: #{e.message}"
end
```

## Advantages

- Handles unstructured text
- Understands context and nuance
- Identifies implicit facts
- Resolves entities automatically

## Disadvantages

- API costs
- Latency
- Occasional errors
- Requires validation

## Best Practices

### 1. Validate Results

```ruby
facts = extractor.extract(content)
facts.each do |fact|
  if fact.confidence < 0.7
    fact.update!(metadata: { needs_review: true })
  end
end
```

### 2. Cache Responses

```ruby
cache_key = "llm:#{content.content_hash}"
facts = Rails.cache.fetch(cache_key) do
  extractor.extract(content)
end
```

### 3. Handle Rate Limits

```ruby
require 'retryable'

Retryable.retryable(tries: 3, sleep: lambda { |n| 2**n }) do
  extractor.extract(content)
end
```
