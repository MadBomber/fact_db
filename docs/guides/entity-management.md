# Entity Management

Entities represent real-world things mentioned in facts - people, organizations, places, and more.

## Creating Entities

### Basic Creation

```ruby
facts = FactDb.new

person = facts.entity_service.create(
  "Paula Chen",
  type: :person
)
```

### With Aliases

```ruby
person = facts.entity_service.create(
  "Paula Chen",
  type: :person,
  aliases: ["Paula", "P. Chen", "Chen, Paula"]
)
```

### With Metadata

```ruby
person = facts.entity_service.create(
  "Paula Chen",
  type: :person,
  aliases: ["Paula"],
  metadata: {
    employee_id: "E12345",
    department: "Engineering",
    start_date: "2024-01-10"
  }
)
```

## Entity Types

| Type | Description | Examples |
|------|-------------|----------|
| `:person` | Individual people | Paula Chen, John Smith |
| `:organization` | Companies, teams | Microsoft, Platform Team |
| `:place` | Locations | San Francisco, Building A |
| `:product` | Products, services | Windows 11, Azure |
| `:event` | Named events | Q4 Earnings, Annual Review |

```ruby
# Custom types are also supported
entity = facts.entity_service.create(
  "TPS Report",
  type: :document_type
)
```

## Managing Aliases

### Add Alias

```ruby
facts.entity_service.add_alias(
  entity.id,
  "P. Chen",
  type: :abbreviation,
  confidence: 0.95
)
```

### Alias Types

| Type | Description |
|------|-------------|
| `nickname` | Informal names |
| `abbreviation` | Shortened forms |
| `formal` | Formal/legal names |
| `maiden_name` | Previous names |
| `trading_name` | Business aliases |

### List Aliases

```ruby
entity.entity_aliases.each do |alias_record|
  puts "#{alias_record.alias_text} (#{alias_record.alias_type})"
  puts "  Confidence: #{alias_record.confidence}"
end
```

### Remove Alias

```ruby
facts.entity_service.remove_alias(entity.id, "Old Name")
```

## Entity Resolution

### Basic Resolution

```ruby
# Resolve a name to an entity
entity = facts.resolve_entity("Paula Chen")

# Returns existing entity or nil if not found
```

### Type-Constrained Resolution

```ruby
# Only match person entities
person = facts.resolve_entity("Paula", type: :person)

# Only match organizations
org = facts.resolve_entity("Microsoft", type: :organization)
```

### Resolution Strategies

The resolver tries in order:

1. **Exact match** on canonical name
2. **Alias match** on registered aliases
3. **Fuzzy match** using Levenshtein distance

```ruby
# Configure fuzzy matching
FactDb.configure do |config|
  config.fuzzy_match_threshold = 0.85  # 85% similarity required
end
```

### Batch Resolution

```ruby
names = ["Paula Chen", "John Smith", "Microsoft", "Seattle"]

results = facts.batch_resolve_entities(names)

results.each do |result|
  status = result[:status]  # :resolved, :not_found, :error
  entity = result[:entity]
  puts "#{result[:name]}: #{status} -> #{entity&.canonical_name}"
end
```

## Merging Entities

When duplicate entities are discovered:

```ruby
# Merge entity2 into entity1 (entity1 is kept)
facts.entity_service.merge(entity1.id, entity2.id)

# After merge:
entity2.reload
entity2.resolution_status  # => "merged"
entity2.merged_into_id     # => entity1.id
```

### What Happens on Merge

1. Entity2's status changes to "merged"
2. Entity2 points to entity1 via `merged_into_id`
3. Entity2's aliases are copied to entity1
4. All facts mentioning entity2 now also reference entity1

### Auto-Merge

Configure automatic merging for high-confidence matches:

```ruby
FactDb.configure do |config|
  config.auto_merge_threshold = 0.95  # Auto-merge at 95% similarity
end
```

## Updating Entities

### Update Canonical Name

```ruby
facts.entity_service.update(
  entity.id,
  canonical_name: "Paula M. Chen"
)
```

### Update Metadata

```ruby
facts.entity_service.update(
  entity.id,
  metadata: entity.metadata.merge(title: "Senior Principal Engineer")
)
```

### Change Type

```ruby
# Reclassify entity type
facts.entity_service.update(
  entity.id,
  entity_type: :organization
)
```

## Resolution Status

| Status | Description |
|--------|-------------|
| `unresolved` | Entity created but not confirmed |
| `resolved` | Entity identity confirmed |
| `merged` | Entity merged into another |

### Mark as Resolved

```ruby
facts.entity_service.update(
  entity.id,
  resolution_status: :resolved
)
```

### Find Unresolved

```ruby
unresolved = FactDb::Models::Entity
  .where(resolution_status: 'unresolved')
  .order(created_at: :desc)
```

## Querying Entities

### Find by ID

```ruby
entity = facts.entity_service.find(entity_id)
```

### Search by Name

```ruby
entities = facts.entity_service.search("Paula")
```

### Filter by Type

```ruby
people = FactDb::Models::Entity
  .where(entity_type: 'person')
  .where.not(resolution_status: 'merged')
```

### Find Entities in Content

```ruby
# Find all entities mentioned in a content
entities = facts.entity_service.in_content(content.id)
```

### Find Related Entities

```ruby
# Entities mentioned in facts about Paula
related = facts.entity_service.related_to(paula.id)
```

## Semantic Search

Search entities by meaning:

```ruby
# Find entities similar to a description
similar = facts.entity_service.semantic_search(
  "software engineering leadership",
  type: :person,
  limit: 10
)
```

## Best Practices

### 1. Use Comprehensive Aliases

```ruby
entity = facts.entity_service.create(
  "International Business Machines Corporation",
  type: :organization,
  aliases: [
    "IBM",
    "Big Blue",
    "International Business Machines",
    "IBM Corp",
    "IBM Corporation"
  ]
)
```

### 2. Store Relevant Metadata

```ruby
person = facts.entity_service.create(
  "Paula Chen",
  type: :person,
  metadata: {
    # Stable identifiers
    employee_id: "E12345",
    linkedin_url: "linkedin.com/in/paulachen",

    # Useful context
    department: "Engineering",
    location: "San Francisco"
  }
)
```

### 3. Review Unresolved Entities

```ruby
# Periodically review unresolved entities
unresolved = FactDb::Models::Entity
  .where(resolution_status: 'unresolved')
  .where('created_at < ?', 1.week.ago)

unresolved.each do |entity|
  # Try to find duplicates
  similar = facts.entity_service.search(entity.canonical_name)
  if similar.count > 1
    puts "Potential duplicate: #{entity.canonical_name}"
  end
end
```

### 4. Handle Merged Entities

```ruby
# When querying, exclude merged entities
active_entities = FactDb::Models::Entity
  .where.not(resolution_status: 'merged')

# Or follow the merge chain
def canonical_entity(entity)
  while entity.merged_into_id
    entity = FactDb::Models::Entity.find(entity.merged_into_id)
  end
  entity
end
```

### 5. Validate Entity Types

```ruby
VALID_TYPES = %i[person organization place product event].freeze

def create_entity(name, type:)
  unless VALID_TYPES.include?(type.to_sym)
    raise ArgumentError, "Invalid entity type: #{type}"
  end
  facts.entity_service.create(name, type: type)
end
```
