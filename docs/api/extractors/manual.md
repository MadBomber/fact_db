# ManualExtractor

API-driven fact creation for maximum control and accuracy.

## Class: `FactDb::Extractors::ManualExtractor`

The ManualExtractor doesn't automatically extract facts - instead it provides a structured interface for creating facts programmatically.

## Usage

```ruby
extractor = FactDb::Extractors::ManualExtractor.new(config)
```

## Methods

### extract

```ruby
def extract(content)
```

Returns an empty array - manual extraction is done via direct fact creation.

**Returns:** `[]`

## When to Use

- High-stakes facts that require human verification
- Structured data import from external systems
- Fact correction or adjustment
- Initial seeding of the system

## Creating Facts Manually

Instead of using the extractor, create facts directly:

```ruby
facts = FactDb.new

# Create entities
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
    { content: announcement, type: "primary", excerpt: "...accepted the offer..." }
  ],
  confidence: 1.0
)
```

## Bulk Import Pattern

```ruby
# Import from structured data
data = [
  { text: "Fact 1", date: "2024-01-01", entity: "Paula" },
  { text: "Fact 2", date: "2024-01-15", entity: "Paula" }
]

data.each do |item|
  entity = facts.resolve_entity(item[:entity])

  facts.fact_service.create(
    item[:text],
    valid_at: Date.parse(item[:date]),
    mentions: [{ entity: entity, role: "subject", text: item[:entity] }],
    extraction_method: "manual"
  )
end
```

## Advantages

- Complete control over fact creation
- Highest accuracy (human-verified)
- No LLM costs
- Works without external dependencies

## Disadvantages

- Labor intensive
- Not scalable for large volumes
- Requires domain expertise
