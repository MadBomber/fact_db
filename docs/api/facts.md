# Facts

The main interface for FactDb operations.

## Class: `FactDb::Facts`

```ruby
facts = FactDb.new
# or
facts = FactDb::Facts.new(config: custom_config)
```

## Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `config` | Config | Configuration instance |
| `source_service` | SourceService | Service for source operations |
| `entity_service` | EntityService | Service for entity operations |
| `fact_service` | FactService | Service for fact operations |
| `extraction_pipeline` | ExtractionPipeline | Pipeline for batch extraction |
| `resolution_pipeline` | ResolutionPipeline | Pipeline for batch resolution |

## Methods

### initialize

```ruby
def initialize(config: nil)
```

Create a new Facts instance.

**Parameters:**

- `config` (Config, optional) - Configuration instance. Uses `FactDb.config` if not provided.

**Example:**

```ruby
# Use default configuration
facts = FactDb.new

# Use custom configuration
config = FactDb::Config.new
config.database.url = "postgresql://localhost/my_db"
facts = FactDb.new(config: config)
```

---

### ingest

```ruby
def ingest(content, kind:, captured_at: Time.current, metadata: {}, title: nil, source_uri: nil)
```

Ingest raw content into the fact database.

**Parameters:**

- `content` (String) - The source text content
- `kind` (Symbol) - Content kind (:email, :document, :article, etc.)
- `captured_at` (Time, optional) - When content was captured
- `metadata` (Hash, optional) - Additional metadata
- `title` (String, optional) - Content title
- `source_uri` (String, optional) - Original location

**Returns:** `Models::Source`

**Example:**

```ruby
source = facts.ingest(
  "Paula joined Microsoft on Jan 10, 2024",
  kind: :announcement,
  title: "New Hire",
  captured_at: Time.current
)
```

---

### extract_facts

```ruby
def extract_facts(source_id, extractor: @config.default_extractor)
```

Extract facts from content.

**Parameters:**

- `source_id` (Integer) - Source ID
- `extractor` (Symbol, optional) - Extraction method (:manual, :llm, :rule_based)

**Returns:** `Array<Models::Fact>`

**Example:**

```ruby
extracted = facts.extract_facts(source.id, extractor: :llm)
```

---

### query_facts

```ruby
def query_facts(topic: nil, at: nil, entity: nil, status: :canonical)
```

Query facts with temporal and entity filtering.

**Parameters:**

- `topic` (String, optional) - Text search query
- `at` (Date/Time, optional) - Point in time (nil = current)
- `entity` (Integer, optional) - Entity ID filter
- `status` (Symbol, optional) - Fact status filter

**Returns:** `ActiveRecord::Relation<Models::Fact>`

**Example:**

```ruby
# Current facts about Paula
results = facts.query_facts(entity: paula.id)

# Facts on a topic
results = facts.query_facts(topic: "engineering")

# Historical query
results = facts.query_facts(at: Date.parse("2023-06-15"))
```

---

### resolve_entity

```ruby
def resolve_entity(name, kind: nil)
```

Resolve a name to an entity.

**Parameters:**

- `name` (String) - Name to resolve
- `kind` (Symbol, optional) - Entity kind filter

**Returns:** `Models::Entity` or `nil`

**Example:**

```ruby
entity = facts.resolve_entity("Paula Chen", kind: :person)
```

---

### timeline_for

```ruby
def timeline_for(entity_id, from: nil, to: nil)
```

Build a timeline for an entity.

**Parameters:**

- `entity_id` (Integer) - Entity ID
- `from` (Date/Time, optional) - Start of range
- `to` (Date/Time, optional) - End of range

**Returns:** `Array<Models::Fact>`

**Example:**

```ruby
timeline = facts.timeline_for(paula.id, from: "2023-01-01", to: "2024-12-31")
```

---

### current_facts_for

```ruby
def current_facts_for(entity_id)
```

Get currently valid facts about an entity.

**Parameters:**

- `entity_id` (Integer) - Entity ID

**Returns:** `ActiveRecord::Relation<Models::Fact>`

**Example:**

```ruby
current = facts.current_facts_for(paula.id)
```

---

### facts_at

```ruby
def facts_at(at, entity: nil, topic: nil)
```

Get facts valid at a specific point in time.

**Parameters:**

- `at` (Date/Time) - Point in time
- `entity` (Integer, optional) - Entity ID filter
- `topic` (String, optional) - Text search query

**Returns:** `ActiveRecord::Relation<Models::Fact>`

**Example:**

```ruby
historical = facts.facts_at(Date.parse("2023-06-15"), entity: paula.id)
```

---

### batch_extract

```ruby
def batch_extract(source_ids, extractor: @config.default_extractor, parallel: true)
```

Batch extract facts from multiple content items.

**Parameters:**

- `source_ids` (Array<Integer>) - Source IDs to process
- `extractor` (Symbol, optional) - Extraction method
- `parallel` (Boolean, optional) - Use parallel processing (default: true)

**Returns:** `Array<Hash>` - Results per content

**Example:**

```ruby
results = facts.batch_extract([s1.id, s2.id, s3.id], parallel: true)
results.each do |r|
  puts "#{r[:source_id]}: #{r[:facts].count} facts"
end
```

---

### batch_resolve_entities

```ruby
def batch_resolve_entities(names, kind: nil)
```

Batch resolve entity names.

**Parameters:**

- `names` (Array<String>) - Names to resolve
- `kind` (Symbol, optional) - Entity kind filter

**Returns:** `Array<Hash>` - Resolution results

**Example:**

```ruby
results = facts.batch_resolve_entities(["Paula", "Microsoft"])
```

---

### detect_fact_conflicts

```ruby
def detect_fact_conflicts(entity_ids)
```

Detect fact conflicts for multiple entities.

**Parameters:**

- `entity_ids` (Array<Integer>) - Entity IDs to check

**Returns:** `Array<Hash>` - Conflict detection results

**Example:**

```ruby
conflicts = facts.detect_fact_conflicts([paula.id, john.id])
```
