# Temporal Queries

FactDb's temporal query system lets you retrieve facts across time - what's true now, what was true then, and how things changed.

## Current Facts

Get facts that are valid right now:

```ruby
facts = FactDb.new

# All currently valid canonical facts
current = facts.query_facts(status: :canonical)

# Current facts about a specific entity
current_about_paula = facts.current_facts_for(paula.id)

# Current facts on a topic
engineering_facts = facts.query_facts(topic: "engineering", status: :canonical)
```

## Point-in-Time Queries

What was true at a specific moment:

```ruby
# What did we know about Paula on June 15, 2023?
historical = facts.facts_at(
  Date.parse("2023-06-15"),
  entity: paula.id
)

# What did we know about Microsoft on Jan 1, 2024?
microsoft_facts = facts.facts_at(
  Date.parse("2024-01-01"),
  entity: microsoft.id
)
```

## Time Range Queries

Facts active during a period:

```ruby
# Facts valid during Q4 2023
q4_facts = facts.fact_service.query(
  from: Date.parse("2023-10-01"),
  to: Date.parse("2023-12-31")
)

# Paula's employment history for 2023
paula_2023 = facts.fact_service.query(
  entity: paula.id,
  from: Date.parse("2023-01-01"),
  to: Date.parse("2023-12-31")
)
```

## Timelines

Build complete timelines for entities:

```ruby
# Full timeline
timeline = facts.timeline_for(paula.id)

timeline.each do |fact|
  range = fact.invalid_at ? "#{fact.valid_at} - #{fact.invalid_at}" : "#{fact.valid_at} - present"
  puts "#{range}: #{fact.text}"
end

# Timeline for specific period
timeline = facts.timeline_for(
  paula.id,
  from: Date.parse("2023-01-01"),
  to: Date.parse("2024-12-31")
)
```

### Timeline Output Example

```
2022-03-15 - 2023-01-09: Paula Chen is Software Engineer at Company
2023-01-10 - 2024-01-09: Paula Chen is Senior Engineer at Company
2024-01-10 - present: Paula Chen is Principal Engineer at Microsoft
```

## Filtering by Status

Query facts by their status:

```ruby
# Only canonical (current authoritative) facts
canonical = facts.query_facts(status: :canonical)

# Only corroborated (confirmed by multiple sources) facts
corroborated = facts.query_facts(status: :corroborated)

# Include both canonical and corroborated
trusted = facts.query_facts(status: [:canonical, :corroborated])

# Superseded facts (historical)
superseded = facts.query_facts(status: :superseded)

# Synthesized facts (derived)
synthesized = facts.query_facts(status: :synthesized)
```

## Topic Search

Search facts by text content:

```ruby
# Full-text search
engineering_facts = facts.query_facts(topic: "engineering")

# Combined with entity filter
paula_engineering = facts.query_facts(
  entity: paula.id,
  topic: "promotion"
)

# Combined with time filter
recent_engineering = facts.query_facts(
  topic: "engineering",
  at: Date.today
)
```

## Advanced Queries

### Using Scopes

```ruby
# Direct ActiveRecord queries on Fact model
facts = FactDb::Models::Fact
  .canonical
  .currently_valid
  .mentioning_entity(paula.id)
  .search_text("engineer")
  .order(valid_at: :desc)
```

### Available Scopes

| Scope | Description |
|-------|-------------|
| `canonical` | Status is 'canonical' |
| `currently_valid` | invalid_at is nil |
| `valid_at(date)` | Valid at specific date |
| `valid_during(from, to)` | Valid during range |
| `mentioning_entity(id)` | Mentions specific entity |
| `search_text(query)` | Full-text search |
| `by_extraction_method(method)` | Filter by extractor |
| `high_confidence` | Confidence > 0.8 |

### Combining Scopes

```ruby
# High-confidence facts about Paula currently valid
facts = FactDb::Models::Fact
  .mentioning_entity(paula.id)
  .canonical
  .currently_valid
  .high_confidence

# LLM-extracted facts from last month
facts = FactDb::Models::Fact
  .by_extraction_method('llm')
  .where('created_at > ?', 1.month.ago)
```

## Semantic Search

Search by meaning using embeddings:

```ruby
# Find facts semantically similar to a query
similar_facts = facts.fact_service.semantic_search(
  "Paula's career progression",
  limit: 10
)

# Combined with entity filter
similar_about_paula = facts.fact_service.semantic_search(
  "job title changes",
  entity: paula.id,
  limit: 5
)
```

## Query Results

### Fact Attributes

```ruby
fact = facts.query_facts(entity: paula.id).first

fact.text        # The assertion text
fact.valid_at         # When it became true
fact.invalid_at       # When it stopped (nil if current)
fact.status           # canonical, superseded, etc.
fact.confidence       # 0.0 to 1.0
fact.extraction_method # manual, llm, rule_based
fact.metadata         # Additional data
```

### Related Data

```ruby
# Entity mentions
fact.entity_mentions.each do |mention|
  puts "#{mention.entity.name} (#{mention.mention_role})"
end

# Source content
fact.fact_sources.each do |fact_source|
  puts "Source: #{fact_source.source.title}"
  puts "Excerpt: #{fact_source.excerpt}"
end

# Superseding fact
if fact.superseded?
  new_fact = fact.superseded_by
  puts "Superseded by: #{new_fact.text}"
end

# Source facts (for synthesized)
if fact.synthesized?
  fact.derived_from_ids.each do |id|
    source = FactDb::Models::Fact.find(id)
    puts "Derived from: #{source.text}"
  end
end
```

## Performance Tips

### Use Indexes

The temporal indexes are optimized for:

```ruby
# These queries are fast
facts.facts_at(Date.today)
facts.query_facts(entity: id, status: :canonical)
```

### Limit Results

```ruby
# Always limit when possible
queried = facts.fact_service.query(
  entity: paula.id,
  limit: 100
)
```

### Eager Load Associations

```ruby
facts = FactDb::Models::Fact
  .includes(:entity_mentions, :fact_sources)
  .mentioning_entity(paula.id)
```

### Use Count for Totals

```ruby
# Don't load all records just to count
total = FactDb::Models::Fact.canonical.currently_valid.count
```

## Common Patterns

### Before/After Comparison

```ruby
# What changed for Paula?
before = facts.facts_at(Date.parse("2023-12-31"), entity: paula.id)
after = facts.facts_at(Date.parse("2024-01-31"), entity: paula.id)

# Find differences
new_facts = after - before
```

### Audit Trail

```ruby
# Get complete history of a topic
all_facts = FactDb::Models::Fact
  .mentioning_entity(paula.id)
  .search_text("title")
  .order(valid_at: :asc)

all_facts.each do |fact|
  status_info = fact.superseded? ? "(superseded)" : "(current)"
  puts "#{fact.valid_at}: #{fact.text} #{status_info}"
end
```

### Change Detection

```ruby
# Find facts that changed recently
recently_superseded = FactDb::Models::Fact
  .where(status: 'superseded')
  .where('invalid_at > ?', 1.week.ago)
  .includes(:superseded_by)

recently_superseded.each do |old_fact|
  puts "Changed: #{old_fact.text}"
  puts "To: #{old_fact.superseded_by.text}"
end
```
