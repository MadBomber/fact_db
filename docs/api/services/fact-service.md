# FactService

Service for extracting and querying facts.

## Class: `FactDb::Services::FactService`

```ruby
service = FactDb::Services::FactService.new(config)
```

## Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `resolver` | FactResolver | For fact resolution operations |

## Methods

### create

```ruby
def create(fact_text, valid_at:, invalid_at: nil, mentions: [], sources: [], confidence: 1.0, metadata: {})
```

Create a new fact.

**Parameters:**

- `fact_text` (String) - The assertion
- `valid_at` (Date/Time) - When fact became true
- `invalid_at` (Date/Time) - When fact stopped (optional)
- `mentions` (Array) - Entity mentions
- `sources` (Array) - Source content links
- `confidence` (Float) - Extraction confidence
- `metadata` (Hash) - Additional data

**Returns:** `Models::Fact`

**Example:**

```ruby
fact = service.create(
  "Paula Chen is Principal Engineer",
  valid_at: Date.parse("2024-01-10"),
  mentions: [
    { entity: paula, role: "subject", text: "Paula Chen" }
  ],
  sources: [
    { content: email, type: "primary" }
  ]
)
```

---

### find

```ruby
def find(id)
```

Find fact by ID.

**Returns:** `Models::Fact`

---

### extract_from_content

```ruby
def extract_from_content(content_id, extractor: config.default_extractor)
```

Extract facts from content using specified extractor.

**Parameters:**

- `content_id` (Integer) - Content ID
- `extractor` (Symbol) - Extractor type (:manual, :llm, :rule_based)

**Returns:** `Array<Models::Fact>`

**Example:**

```ruby
facts = service.extract_from_content(content.id, extractor: :llm)
```

---

### query

```ruby
def query(topic: nil, at: nil, entity: nil, status: :canonical, from: nil, to: nil, limit: nil)
```

Query facts with filters.

**Parameters:**

- `topic` (String) - Text search
- `at` (Date/Time) - Point in time
- `entity` (Integer) - Entity ID
- `status` (Symbol/Array) - Status filter
- `from` (Date/Time) - Range start
- `to` (Date/Time) - Range end
- `limit` (Integer) - Max results

**Returns:** `ActiveRecord::Relation`

**Example:**

```ruby
# Current facts about Paula
facts = service.query(entity: paula.id, status: :canonical)

# Historical facts
facts = service.query(entity: paula.id, at: Date.parse("2023-06-15"))

# Facts in a range
facts = service.query(
  entity: paula.id,
  from: Date.parse("2023-01-01"),
  to: Date.parse("2023-12-31")
)
```

---

### timeline

```ruby
def timeline(entity_id:, from: nil, to: nil)
```

Build a timeline for an entity.

**Returns:** `Array<Models::Fact>`

**Example:**

```ruby
timeline = service.timeline(entity_id: paula.id)
timeline.each do |fact|
  puts "#{fact.valid_at}: #{fact.fact_text}"
end
```

---

### from_content

```ruby
def from_content(content_id)
```

Get facts sourced from specific content.

**Returns:** `Array<Models::Fact>`

---

### semantic_search

```ruby
def semantic_search(query, entity: nil, limit: 10)
```

Semantic similarity search.

**Returns:** `Array<Models::Fact>`

## Resolver Methods

Access via `service.resolver`:

### supersede

```ruby
service.resolver.supersede(old_fact_id, new_text, valid_at: date)
```

Supersede an existing fact.

### synthesize

```ruby
service.resolver.synthesize(source_ids, synthesized_text, valid_at: date)
```

Create synthesized fact from multiple sources.

### corroborate

```ruby
service.resolver.corroborate(fact_id, corroborating_fact_id)
```

Mark fact as corroborated.

### invalidate

```ruby
service.resolver.invalidate(fact_id, at: Time.current)
```

Invalidate a fact.

### find_conflicts

```ruby
service.resolver.find_conflicts(entity_id: id, topic: text)
```

Find potentially conflicting facts.

### resolve_conflict

```ruby
service.resolver.resolve_conflict(keep_id, supersede_ids, reason: text)
```

Resolve conflicts by keeping one fact.
