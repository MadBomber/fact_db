# Source Model

Stores immutable source content from which facts are extracted.

## Class: `FactDb::Models::Source`

```ruby
source = FactDb::Models::Source.new(
  content: "Document content...",
  type: "email",
  captured_at: Time.current
)
```

## Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | Integer | Primary key |
| `content_hash` | String | SHA256 hash for deduplication |
| `type` | String | Type (email, document, etc.) |
| `content` | Text | Original unmodified text content |
| `title` | String | Optional title |
| `source_uri` | String | Original location |
| `source_metadata` | Hash | Additional metadata (JSONB) |
| `embedding` | Vector | Semantic search vector |
| `captured_at` | DateTime | When content was captured |
| `created_at` | DateTime | Record creation time |

## Associations

```ruby
has_many :fact_sources
has_many :facts, through: :fact_sources
```

## Callbacks

```ruby
before_create :compute_hash
before_create :generate_embedding
```

## Instance Methods

### compute_hash

```ruby
def compute_hash
```

Computes SHA256 hash of content for deduplication.

### generate_embedding

```ruby
def generate_embedding
```

Generates embedding vector using configured generator.

## Class Methods

### find_or_create_by_text

```ruby
def self.find_or_create_by_text(text, **attributes)
```

Find existing source by hash or create new.

**Example:**

```ruby
source = Source.find_or_create_by_text(
  "Document text",
  type: "document",
  captured_at: Time.current
)
```

## Scopes

### by_type

```ruby
scope :by_type, ->(type) { where(type: type) }
```

Filter by content type.

```ruby
Source.by_type('email')
```

### captured_between

```ruby
scope :captured_between, ->(from, to) {
  where(captured_at: from..to)
}
```

Filter by capture date range.

```ruby
Source.captured_between(1.week.ago, Time.current)
```

### search_text

```ruby
scope :search_text, ->(query) {
  where("content @@ plainto_tsquery(?)", query)
}
```

Full-text search.

```ruby
Source.search_text("quarterly earnings")
```

## Usage Examples

### Create Source

```ruby
source = Source.create!(
  content: "Important document...",
  type: "document",
  title: "Q4 Report",
  source_uri: "https://example.com/report.pdf",
  captured_at: Time.current,
  source_metadata: {
    author: "Jane Smith",
    department: "Finance"
  }
)
```

### Find by Hash

```ruby
hash = Digest::SHA256.hexdigest("Document text")
source = Source.find_by(content_hash: hash)
```

### Get Related Facts

```ruby
source.facts.each do |fact|
  puts fact.fact_text
end
```

### Semantic Search

```ruby
# Requires embedding
similar = Source
  .where.not(embedding: nil)
  .order(Arel.sql("embedding <=> '#{query_embedding}'"))
  .limit(10)
```
