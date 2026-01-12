# Entity Model

Stores resolved identities (people, organizations, places, etc.).

## Class: `FactDb::Models::Entity`

```ruby
entity = FactDb::Models::Entity.new(
  name: "Paula Chen",
  type: "person"
)
```

## Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | Integer | Primary key |
| `name` | String | Authoritative name |
| `type` | String | Type (person, organization, place, etc.) |
| `resolution_status` | String | Status (unresolved, resolved, merged) |
| `canonical_id` | Integer | Points to canonical entity if merged |
| `metadata` | Hash | Additional attributes (JSONB) |
| `embedding` | Vector | Semantic search vector |
| `created_at` | DateTime | Record creation time |

## Entity Types

- `person` - Individual people
- `organization` - Companies, teams, groups
- `place` - Locations
- `product` - Products, services
- `event` - Named events

## Resolution Status

- `unresolved` - Entity created but not confirmed
- `resolved` - Entity identity confirmed
- `merged` - Entity merged into another

## Associations

```ruby
has_many :entity_aliases, dependent: :destroy
has_many :entity_mentions
has_many :facts, through: :entity_mentions
belongs_to :merged_into, class_name: 'Entity', optional: true
```

## Instance Methods

### add_alias

```ruby
def add_alias(text, type: nil, confidence: 1.0)
```

Add an alias to the entity.

**Example:**

```ruby
entity.add_alias("Paula", type: "nickname", confidence: 0.95)
```

### merged?

```ruby
def merged?
```

Returns true if entity has been merged into another.

### canonical

```ruby
def canonical
```

Returns the canonical entity (follows merge chain).

**Example:**

```ruby
# If entity was merged
canonical = entity.canonical  # Returns the canonical entity
```

## Scopes

### by_type

```ruby
scope :by_type, ->(t) { where(type: t) }
```

Filter by entity type.

```ruby
Entity.by_type('person')
```

### active

```ruby
scope :active, -> { where.not(resolution_status: 'merged') }
```

Exclude merged entities.

```ruby
Entity.active
```

### resolved

```ruby
scope :resolved, -> { where(resolution_status: 'resolved') }
```

Only resolved entities.

### search_name

```ruby
scope :search_name, ->(query) {
  where("name ILIKE ?", "%#{query}%")
}
```

Search by name.

```ruby
Entity.search_name("paula")
```

## Usage Examples

### Create Entity

```ruby
entity = Entity.create!(
  name: "Paula Chen",
  type: "person",
  metadata: {
    department: "Engineering",
    employee_id: "E12345"
  }
)
```

### Add Aliases

```ruby
entity.add_alias("Paula")
entity.add_alias("P. Chen", type: "abbreviation")
entity.add_alias("Chen, Paula", type: "formal")
```

### Check Aliases

```ruby
entity.entity_aliases.each do |a|
  puts "#{a.name} (#{a.type})"
end
```

### Get Related Facts

```ruby
entity.facts.each do |fact|
  puts "#{fact.valid_at}: #{fact.fact_text}"
end
```

### Find Similar Entities

```ruby
# By name
similar = Entity.search_name("Microsoft")

# By embedding
similar = Entity
  .where.not(embedding: nil)
  .order(Arel.sql("embedding <=> '#{query_embedding}'"))
  .limit(10)
```

### Merge Entities

```ruby
# entity2 will be merged into entity1
entity2.update!(
  resolution_status: 'merged',
  canonical_id: entity1.id
)

# Copy aliases
entity2.entity_aliases.each do |a|
  entity1.add_alias(a.name, type: a.type)
end
```
