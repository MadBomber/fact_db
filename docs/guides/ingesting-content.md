# Ingesting Content

Content is the foundation of FactDb - immutable source documents from which facts are extracted.

## Basic Ingestion

```ruby
facts = FactDb.new

content = facts.ingest(
  "Paula Chen joined Microsoft as Principal Engineer on January 10, 2024.",
  type: :announcement
)
```

## Full Options

```ruby
content = facts.ingest(
  raw_text,
  type: :email,
  title: "RE: Offer Letter - Paula Chen",
  source_uri: "mailto:hr@company.com/msg/12345",
  captured_at: Time.parse("2024-01-08 10:30:00"),
  metadata: {
    from: "hr@company.com",
    to: "hiring@company.com",
    cc: ["manager@company.com"],
    subject: "RE: Offer Letter - Paula Chen",
    thread_id: "THR-12345"
  }
)
```

## Content Types

Choose a type that best describes the source:

| Type | Use Case |
|------|----------|
| `:email` | Email messages |
| `:document` | General documents, PDFs |
| `:article` | News articles, blog posts |
| `:transcript` | Meeting transcripts, interviews |
| `:report` | Reports, analysis documents |
| `:announcement` | Official announcements |
| `:social` | Social media posts |
| `:form` | Structured forms, surveys |
| `:note` | Notes, memos |

```ruby
# Custom types are also allowed
content = facts.ingest(text, type: :slack_message)
```

## Metadata

Store additional context in metadata:

```ruby
# Email metadata
metadata: {
  from: "sender@example.com",
  to: "recipient@example.com",
  subject: "Important Update",
  message_id: "<abc123@mail.example.com>"
}

# Document metadata
metadata: {
  author: "Jane Smith",
  version: "2.1",
  department: "Engineering",
  classification: "internal"
}

# Article metadata
metadata: {
  author: "John Doe",
  publication: "Tech News",
  url: "https://technews.com/article/123",
  published_at: "2024-01-15T14:30:00Z"
}
```

## Deduplication

Content is automatically deduplicated by SHA256 hash:

```ruby
# First ingestion - creates new record
content1 = facts.ingest("Hello world", type: :note)

# Second ingestion - returns existing record
content2 = facts.ingest("Hello world", type: :note)

content1.id == content2.id  # => true
```

## Timestamps

### captured_at

When the content was captured/received (defaults to current time):

```ruby
# Email received yesterday
content = facts.ingest(
  email_body,
  type: :email,
  captured_at: Time.parse("2024-01-14 09:00:00")
)
```

### created_at

Automatically set when record is created (system timestamp).

## Batch Ingestion

For multiple documents:

```ruby
documents = [
  { text: "Doc 1 content", type: :document, title: "Doc 1" },
  { text: "Doc 2 content", type: :document, title: "Doc 2" },
  { text: "Doc 3 content", type: :document, title: "Doc 3" }
]

contents = documents.map do |doc|
  facts.ingest(doc[:text], type: doc[:type], title: doc[:title])
end
```

## Content Service

For advanced operations, use the content service directly:

```ruby
# Create content
content = facts.content_service.create(
  raw_text,
  type: :document,
  title: "Annual Report"
)

# Find by ID
content = facts.content_service.find(content_id)

# Find by hash
content = facts.content_service.find_by_hash(sha256_hash)

# Search by text
results = facts.content_service.search("quarterly earnings")

# Semantic search (requires embedding)
results = facts.content_service.semantic_search(
  "financial performance",
  limit: 10
)
```

## Embeddings

If you configure an embedding generator, content embeddings are created automatically:

```ruby
FactDb.configure do |config|
  config.embedding_generator = ->(text) {
    # Your embedding logic
    client.embeddings(input: text)
  }
end

# Embeddings generated on ingest
content = facts.ingest(text, type: :document)
content.embedding  # => [0.123, -0.456, ...]
```

## Source URIs

Track original locations with source_uri:

```ruby
# Email
source_uri: "mailto:sender@example.com/msg/12345"

# Web page
source_uri: "https://example.com/articles/123"

# File
source_uri: "file:///path/to/document.pdf"

# Database record
source_uri: "db://crm/contacts/12345"

# API
source_uri: "api://salesforce/leads/ABC123"
```

## Best Practices

### 1. Preserve Original Text

```ruby
# Good - preserve original formatting
facts.ingest(original_email_body, type: :email)

# Avoid - don't pre-process
facts.ingest(cleaned_text.strip.downcase, type: :email)
```

### 2. Include Context in Metadata

```ruby
content = facts.ingest(
  transcript,
  type: :transcript,
  title: "Q4 2024 Earnings Call",
  metadata: {
    participants: ["CEO", "CFO", "Analysts"],
    duration_minutes: 60,
    recording_url: "https://..."
  }
)
```

### 3. Use Consistent Types

```ruby
# Define content types for your organization
module ContentTypes
  EMAIL = :email
  SLACK = :slack_message
  MEETING = :meeting_transcript
  # ...
end

facts.ingest(text, type: ContentTypes::EMAIL)
```

### 4. Track Source

```ruby
# Always include source information for audit trails
content = facts.ingest(
  text,
  type: :document,
  source_uri: "sharepoint://documents/annual-report-2024.pdf",
  metadata: { uploaded_by: "jane@company.com" }
)
```
