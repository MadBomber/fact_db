# SourceService

Service for ingesting and managing source content.

## Class: `FactDb::Services::SourceService`

```ruby
service = FactDb::Services::SourceService.new(config)
```

## Methods

### create

```ruby
def create(content, kind:, captured_at: Time.current, metadata: {}, title: nil, source_uri: nil)
```

Create new source with automatic deduplication.

**Parameters:**

- `content` (String) - Source text content
- `kind` (Symbol) - Content kind
- `captured_at` (Time) - Capture timestamp
- `metadata` (Hash) - Additional metadata
- `title` (String) - Optional title
- `source_uri` (String) - Original location

**Returns:** `Models::Source`

**Example:**

```ruby
source = service.create(
  "Email body text...",
  kind: :email,
  title: "RE: Important",
  metadata: { from: "sender@example.com" }
)
```

---

### find

```ruby
def find(id)
```

Find source by ID.

**Returns:** `Models::Source`

---

### find_by_hash

```ruby
def find_by_hash(hash)
```

Find source by SHA256 hash.

**Returns:** `Models::Source` or `nil`

**Example:**

```ruby
hash = Digest::SHA256.hexdigest(text)
source = service.find_by_hash(hash)
```

---

### search

```ruby
def search(query, limit: 20)
```

Full-text search sources.

**Parameters:**

- `query` (String) - Search query
- `limit` (Integer) - Max results

**Returns:** `Array<Models::Source>`

**Example:**

```ruby
results = service.search("quarterly report", limit: 10)
```

---

### semantic_search

```ruby
def semantic_search(query, limit: 10)
```

Semantic similarity search using embeddings.

**Parameters:**

- `query` (String) - Search query
- `limit` (Integer) - Max results

**Returns:** `Array<Models::Source>`

**Example:**

```ruby
results = service.semantic_search("financial performance")
```

---

### by_kind

```ruby
def by_kind(kind)
```

Filter sources by kind.

**Returns:** `ActiveRecord::Relation`

**Example:**

```ruby
emails = service.by_kind(:email)
```

---

### recent

```ruby
def recent(limit: 20)
```

Get recently captured sources.

**Returns:** `Array<Models::Source>`

---

### mentioning_entity

```ruby
def mentioning_entity(entity_id)
```

Find sources that mention an entity (via facts).

**Returns:** `Array<Models::Source>`

**Example:**

```ruby
paula_sources = service.mentioning_entity(paula.id)
```
