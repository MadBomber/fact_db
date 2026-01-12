# Extracting Facts

Facts are extracted from content using one of three methods: manual, LLM-powered, or rule-based.

## Extraction Methods

### Manual Extraction

Create facts directly via the API:

```ruby
facts = FactDb.new

# Create entities first
paula = facts.entity_service.create("Paula Chen", type: :person)
microsoft = facts.entity_service.create("Microsoft", type: :organization)

# Create fact with explicit links
fact = facts.fact_service.create(
  "Paula Chen joined Microsoft as Principal Engineer",
  valid_at: Date.parse("2024-01-10"),
  mentions: [
    { entity: paula, role: "subject", text: "Paula Chen" },
    { entity: microsoft, role: "organization", text: "Microsoft" }
  ],
  sources: [
    { source: source, type: "primary", excerpt: "...accepted the offer..." }
  ]
)
```

### LLM Extraction

Use AI to automatically extract facts:

```ruby
# Configure LLM
FactDb.configure do |config|
  config.llm.provider = :openai
  config.llm.api_key = ENV['OPENAI_API_KEY']
end

facts = FactDb.new

# Extract facts from source
extracted = facts.extract_facts(source.id, extractor: :llm)

extracted.each do |fact|
  puts fact.fact_text
  puts "  Valid from: #{fact.valid_at}"
  puts "  Entities: #{fact.entity_mentions.map(&:entity).map(&:canonical_name)}"
end
```

### Rule-Based Extraction

Use regex patterns for structured content:

```ruby
extracted = facts.extract_facts(source.id, extractor: :rule_based)
```

The rule-based extractor includes patterns for:

- Dates and time references
- Employment events (joined, promoted, left)
- Title/role changes
- Location references
- Organizational relationships

## Setting Default Extractor

```ruby
FactDb.configure do |config|
  config.default_extractor = :llm  # or :manual, :rule_based
end

# Uses configured default
extracted = facts.extract_facts(source.id)
```

## Fact Structure

Every extracted fact includes:

```ruby
fact = Models::Fact.new(
  fact_text: "Paula Chen is Principal Engineer at Microsoft",
  fact_hash: "sha256...",           # For deduplication
  valid_at: Time.parse("2024-01-10"),
  invalid_at: nil,                   # nil = currently valid
  status: "canonical",               # canonical, superseded, corroborated, synthesized
  confidence: 0.95,                  # Extraction confidence
  extraction_method: "llm",          # manual, llm, rule_based
  metadata: {}                       # Additional data
)
```

## Entity Mentions

Facts link to entities via mentions:

```ruby
fact.add_mention(
  entity: paula,
  text: "Paula Chen",    # How entity was mentioned
  role: "subject",       # Role in the fact
  confidence: 0.95       # Resolution confidence
)
```

### Mention Roles

| Role | Description | Example |
|------|-------------|---------|
| `subject` | Primary actor | "Paula joined..." |
| `object` | Target | "...hired Paula" |
| `organization` | Company/team | "...at Microsoft" |
| `location` | Place | "...in Seattle" |
| `role` | Title/position | "...as Engineer" |
| `temporal` | Time reference | "...in Q4 2024" |
| `attribute` | Property | "...with 10 years experience" |

## Source Links

Facts link to source content:

```ruby
fact.add_source(
  source: email_source,
  type: "primary",
  excerpt: "Paula has accepted our offer to join as Principal Engineer...",
  confidence: 0.95
)
```

### Source Types

| Type | Description |
|------|-------------|
| `primary` | Direct source of the fact |
| `supporting` | Confirms the fact |
| `contradicting` | Contradicts the fact |

## Batch Extraction

Process multiple content items:

```ruby
source_ids = [source1.id, source2.id, source3.id]

# Sequential processing
results = facts.batch_extract(source_ids, parallel: false)

# Parallel processing (default)
results = facts.batch_extract(source_ids, parallel: true)

results.each do |result|
  puts "Source #{result[:source_id]}:"
  puts "  Facts: #{result[:facts].count}"
  puts "  Error: #{result[:error]}" if result[:error]
end
```

## Custom Extractors

Create custom extractors by extending the base class:

```ruby
class MyExtractor < FactDb::Extractors::Base
  def extract(source)
    extracted = []

    # Your extraction logic here
    # Parse source.content
    # Create fact records

    extracted
  end
end

# Register and use
facts.fact_service.extract_from_source(
  source.id,
  extractor: MyExtractor.new(config)
)
```

## Extraction Confidence

Track confidence levels:

```ruby
# High confidence - direct statement
fact = facts.fact_service.create(
  "Paula is Principal Engineer",
  confidence: 0.95
)

# Medium confidence - inferred
fact = facts.fact_service.create(
  "Paula likely works in Engineering",
  confidence: 0.7
)

# Low confidence - speculation
fact = facts.fact_service.create(
  "Paula may be promoted soon",
  confidence: 0.4
)
```

## Post-Extraction Processing

After extraction, you may want to:

### Resolve Entities

```ruby
extracted = facts.extract_facts(source.id, extractor: :llm)

extracted.each do |fact|
  fact.entity_mentions.each do |mention|
    if mention.entity.nil?
      # Resolve unlinked mention
      entity = facts.resolve_entity(mention.mention_text)
      mention.update!(entity: entity) if entity
    end
  end
end
```

### Detect Conflicts

```ruby
conflicts = facts.fact_service.resolver.find_conflicts(
  entity_id: paula.id
)

conflicts.each do |conflict|
  puts "Conflict between:"
  puts "  #{conflict[:fact1].fact_text}"
  puts "  #{conflict[:fact2].fact_text}"
end
```

### Corroborate Facts

```ruby
# If multiple sources say the same thing
if fact1.fact_text.similar_to?(fact2.fact_text)
  facts.fact_service.resolver.corroborate(fact1.id, fact2.id)
end
```

## Best Practices

### 1. Review LLM Extractions

```ruby
extracted = facts.extract_facts(source.id, extractor: :llm)

extracted.select { |f| f.confidence < 0.8 }.each do |fact|
  # Flag for human review
  fact.update!(metadata: fact.metadata.merge(needs_review: true))
end
```

### 2. Validate Temporal Information

```ruby
# Ensure valid_at is reasonable
if fact.valid_at > Time.current
  logger.warn "Future date detected: #{fact.valid_at}"
end
```

### 3. Link Sources

```ruby
# Always link facts to their sources
fact = facts.fact_service.create(
  "Important fact",
  valid_at: Date.today,
  sources: [{ source: source_record, type: "primary" }]
)
```

### 4. Handle Extraction Errors

```ruby
begin
  extracted = facts.extract_facts(source.id, extractor: :llm)
rescue FactDb::ExtractionError => e
  logger.error "Extraction failed: #{e.message}"
  # Fall back to manual or rule-based
  extracted = facts.extract_facts(source.id, extractor: :rule_based)
end
```
