# Services

Services provide the business logic layer for FactDb operations.

## Available Services

- [SourceService](source-service.md) - Ingest and manage source content
- [EntityService](entity-service.md) - Create and resolve entities
- [FactService](fact-service.md) - Extract and query facts

## Service Pattern

All services follow a common pattern:

```ruby
class SomeService
  attr_reader :config

  def initialize(config = FactDb.config)
    @config = config
  end

  # Business methods...
end
```

## Accessing Services

### Via FactDb

```ruby
facts = FactDb.new

facts.source_service.create(text, type: :document)
facts.entity_service.create("Paula", type: :person)
facts.fact_service.create("Fact text", valid_at: Date.today)
```

### Directly

```ruby
service = FactDb::Services::SourceService.new(config)
source = service.create(text, type: :document)
```

## Common Methods

All services provide these common methods:

| Method | Description |
|--------|-------------|
| `find(id)` | Find record by ID |
| `create(...)` | Create new record |
| `update(id, ...)` | Update existing record |
| `search(query)` | Search records |
