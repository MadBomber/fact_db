# ContentService

Service for ingesting and managing source content.

## Class: `FactDb::Services::ContentService`

```ruby
service = FactDb::Services::ContentService.new(config)
```

## Methods

### create

```ruby
def create(raw_text, type:, captured_at: Time.current, metadata: {}, title: nil, source_uri: nil)
```

Create new content with automatic deduplication.

**Parameters:**

- `raw_text` (String) - Content text
- `type` (Symbol) - Content type
- `captured_at` (Time) - Capture timestamp
- `metadata` (Hash) - Additional metadata
- `title` (String) - Optional title
- `source_uri` (String) - Original location

**Returns:** `Models::Content`

**Example:**

```ruby
content = service.create(
  "Email body text...",
  type: :email,
  title: "RE: Important",
  metadata: { from: "sender@example.com" }
)
```

---

### find

```ruby
def find(id)
```

Find content by ID.

**Returns:** `Models::Content`

---

### find_by_hash

```ruby
def find_by_hash(hash)
```

Find content by SHA256 hash.

**Returns:** `Models::Content` or `nil`

**Example:**

```ruby
hash = Digest::SHA256.hexdigest(text)
content = service.find_by_hash(hash)
```

---

### search

```ruby
def search(query, limit: 20)
```

Full-text search content.

**Parameters:**

- `query` (String) - Search query
- `limit` (Integer) - Max results

**Returns:** `Array<Models::Content>`

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

**Returns:** `Array<Models::Content>`

**Example:**

```ruby
results = service.semantic_search("financial performance")
```

---

### by_type

```ruby
def by_type(type)
```

Filter content by type.

**Returns:** `ActiveRecord::Relation`

**Example:**

```ruby
emails = service.by_type(:email)
```

---

### recent

```ruby
def recent(limit: 20)
```

Get recently captured content.

**Returns:** `Array<Models::Content>`

---

### mentioning_entity

```ruby
def mentioning_entity(entity_id)
```

Find content that mentions an entity (via facts).

**Returns:** `Array<Models::Content>`

**Example:**

```ruby
paula_content = service.mentioning_entity(paula.id)
```
