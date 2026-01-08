# Extractors

Extractors are responsible for identifying and creating facts from source content.

## Available Extractors

- [ManualExtractor](manual.md) - API-driven fact creation
- [LLMExtractor](llm.md) - AI-powered extraction
- [RuleBasedExtractor](rule-based.md) - Pattern matching

## Base Class

All extractors inherit from `FactDb::Extractors::Base`:

```ruby
class Base
  attr_reader :config

  def initialize(config = FactDb.config)
    @config = config
  end

  def extract(content)
    raise NotImplementedError
  end

  def extraction_method
    self.class.name.split("::").last.sub("Extractor", "").underscore
  end
end
```

## Creating Custom Extractors

```ruby
class MyExtractor < FactDb::Extractors::Base
  def extract(content)
    facts = []

    # Your extraction logic
    # Parse content.raw_text
    # Create fact records

    facts
  end
end
```

## Using Extractors

### Via Facts

```ruby
facts = FactDb.new
extracted = facts.extract_facts(content.id, extractor: :llm)
```

### Directly

```ruby
extractor = FactDb::Extractors::LLMExtractor.new(config)
facts = extractor.extract(content)
```

## Extractor Selection

| Extractor | Best For | Accuracy | Speed |
|-----------|----------|----------|-------|
| Manual | High-stakes facts | Highest | Slowest |
| LLM | Complex documents | High | Medium |
| Rule-based | Structured content | Medium | Fastest |
