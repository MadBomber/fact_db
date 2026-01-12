# Examples

Practical examples demonstrating FactDb usage patterns.

## Getting Started

- [Basic Usage](basic-usage.md) - Simple introduction to core functionality

## Use Cases

- [HR Onboarding](hr-onboarding.md) - Track employee facts over time
- [News Analysis](news-analysis.md) - Extract facts from news articles

## Common Patterns

### Ingest and Extract

```ruby
facts = FactDb.new

# Ingest content
source = facts.ingest(document_text, type: :document)

# Extract facts
extracted = facts.extract_facts(source.id, extractor: :llm)
```

### Query Current State

```ruby
# What do we know about Paula now?
current = facts.current_facts_for(paula.id)
```

### Historical Query

```ruby
# What did we know on a specific date?
historical = facts.facts_at(Date.parse("2023-06-15"), entity: paula.id)
```

### Timeline

```ruby
# Build complete timeline
timeline = facts.timeline_for(paula.id)
timeline.each do |fact|
  puts "#{fact.valid_at}: #{fact.text}"
end
```

### Entity Resolution

```ruby
# Resolve names to entities
entity = facts.resolve_entity("Paula Chen", type: :person)
```

### Batch Processing

```ruby
# Process multiple documents
results = facts.batch_extract(source_ids, parallel: true)
```
