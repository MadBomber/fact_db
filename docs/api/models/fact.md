# Fact Model

Stores temporal assertions about entities.

## Class: `FactDb::Models::Fact`

```ruby
fact = FactDb::Models::Fact.new(
  text: "Paula Chen is Principal Engineer",
  valid_at: Date.parse("2024-01-10"),
  status: "canonical"
)
```

## Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | Integer | Primary key |
| `text` | Text | The assertion |
| `digest` | String | SHA256 digest for deduplication |
| `valid_at` | DateTime | When fact became true |
| `invalid_at` | DateTime | When fact stopped being true (nil if current) |
| `status` | String | Status (canonical, superseded, corroborated, synthesized) |
| `superseded_by_id` | Integer | Points to replacing fact |
| `derived_from_ids` | Array | Source facts for synthesized |
| `corroborated_by_ids` | Array | Corroborating facts |
| `confidence` | Float | Extraction confidence (0.0-1.0) |
| `extraction_method` | String | How fact was extracted |
| `metadata` | Hash | Additional data (JSONB) |
| `embedding` | Vector | Semantic search vector |
| `created_at` | DateTime | Record creation time |

## Fact Status

- `canonical` - Current authoritative version
- `superseded` - Replaced by newer information
- `corroborated` - Confirmed by multiple sources
- `synthesized` - Derived from multiple facts

## Associations

```ruby
has_many :entity_mentions, dependent: :destroy
has_many :entities, through: :entity_mentions
has_many :fact_sources, dependent: :destroy
has_many :contents, through: :fact_sources
belongs_to :superseded_by, class_name: 'Fact', optional: true
```

## Instance Methods

### add_mention

```ruby
def add_mention(entity:, text:, role:, confidence: 1.0)
```

Add an entity mention to the fact.

**Example:**

```ruby
fact.add_mention(
  entity: paula,
  text: "Paula Chen",
  role: "subject",
  confidence: 0.95
)
```

### add_source

```ruby
def add_source(source:, kind: "primary", excerpt: nil, confidence: 1.0)
```

Add a source content link.

**Example:**

```ruby
fact.add_source(
  source: email,
  kind: "primary",
  excerpt: "...accepted the offer..."
)
```

### currently_valid?

```ruby
def currently_valid?
```

Returns true if fact is currently valid (invalid_at is nil).

### valid_at?(date)

```ruby
def valid_at?(date)
```

Returns true if fact was valid at the given date.

### superseded?

```ruby
def superseded?
```

Returns true if fact has been superseded.

### canonical?

```ruby
def canonical?
```

Returns true if fact is canonical.

## Scopes

### canonical

```ruby
scope :canonical, -> { where(status: 'canonical') }
```

Only canonical facts.

### currently_valid

```ruby
scope :currently_valid, -> { where(invalid_at: nil) }
```

Facts that are currently valid.

### valid_at

```ruby
scope :valid_at, ->(date) {
  where("valid_at <= ? AND (invalid_at IS NULL OR invalid_at > ?)", date, date)
}
```

Facts valid at a specific point in time.

```ruby
Fact.valid_at(Date.parse("2023-06-15"))
```

### mentioning_entity

```ruby
scope :mentioning_entity, ->(entity_id) {
  joins(:entity_mentions).where(entity_mentions: { entity_id: entity_id })
}
```

Facts mentioning a specific entity.

```ruby
Fact.mentioning_entity(paula.id)
```

### search_text

```ruby
scope :search_text, ->(query) {
  where("text @@ plainto_tsquery(?)", query)
}
```

Full-text search.

```ruby
Fact.search_text("engineer")
```

### by_extraction_method

```ruby
scope :by_extraction_method, ->(method) {
  where(extraction_method: method)
}
```

Filter by extraction method.

```ruby
Fact.by_extraction_method('llm')
```

### high_confidence

```ruby
scope :high_confidence, -> { where("confidence > 0.8") }
```

High confidence facts only.

## Usage Examples

### Create Fact

```ruby
fact = Fact.create!(
  text: "Paula Chen joined Microsoft as Principal Engineer",
  valid_at: Date.parse("2024-01-10"),
  status: "canonical",
  extraction_method: "manual",
  confidence: 1.0
)

# Add mentions
fact.add_mention(entity: paula, text: "Paula Chen", role: "subject")
fact.add_mention(entity: microsoft, text: "Microsoft", role: "organization")

# Add source
fact.add_source(source: announcement, kind: "primary")
```

### Query Facts

```ruby
# Current facts about Paula
Fact.canonical.currently_valid.mentioning_entity(paula.id)

# Historical facts
Fact.valid_at(Date.parse("2023-06-15")).mentioning_entity(paula.id)

# Search
Fact.search_text("promoted")
```

### Supersede Fact

```ruby
new_fact = Fact.create!(
  text: "Paula Chen is Senior Principal Engineer",
  valid_at: Date.parse("2024-06-01"),
  status: "canonical"
)

old_fact.update!(
  status: "superseded",
  superseded_by_id: new_fact.id,
  invalid_at: Date.parse("2024-06-01")
)
```

### Get Sources

```ruby
fact.fact_sources.each do |fact_source|
  puts "Source: #{fact_source.source.title}"
  puts "Kind: #{fact_source.kind}"
  puts "Excerpt: #{fact_source.excerpt}"
end
```

### Get Mentioned Entities

```ruby
fact.entity_mentions.each do |mention|
  puts "#{mention.entity.name} (#{mention.mention_role})"
end
```
