# EntityService

Service for creating and resolving entities.

## Class: `FactDb::Services::EntityService`

```ruby
service = FactDb::Services::EntityService.new(config)
```

## Methods

### create

```ruby
def create(name, type:, aliases: [], metadata: {})
```

Create a new entity.

**Parameters:**

- `name` (String) - Authoritative name
- `type` (Symbol) - Entity type
- `aliases` (Array) - Alternative names
- `metadata` (Hash) - Additional attributes

**Returns:** `Models::Entity`

**Example:**

```ruby
entity = service.create(
  "Paula Chen",
  type: :person,
  aliases: ["Paula", "P. Chen"],
  metadata: { department: "Engineering" }
)
```

---

### find

```ruby
def find(id)
```

Find entity by ID.

**Returns:** `Models::Entity`

---

### resolve

```ruby
def resolve(name, type: nil)
```

Resolve a name to an entity using multiple strategies.

**Parameters:**

- `name` (String) - Name to resolve
- `type` (Symbol) - Optional type filter

**Returns:** `Models::Entity` or `nil`

**Example:**

```ruby
entity = service.resolve("Paula Chen", type: :person)
```

---

### add_alias

```ruby
def add_alias(entity_id, alias_name, type: nil, confidence: 1.0)
```

Add an alias to an entity.

**Example:**

```ruby
service.add_alias(entity.id, "P. Chen", type: :abbreviation)
```

---

### remove_alias

```ruby
def remove_alias(entity_id, alias_name)
```

Remove an alias from an entity.

---

### merge

```ruby
def merge(keep_id, merge_id)
```

Merge two entities (merge_id into keep_id).

**Example:**

```ruby
service.merge(canonical_entity.id, duplicate_entity.id)
```

---

### update

```ruby
def update(id, **attributes)
```

Update entity attributes.

**Example:**

```ruby
service.update(
  entity.id,
  name: "Paula M. Chen",
  metadata: { title: "Senior Engineer" }
)
```

---

### search

```ruby
def search(query, type: nil, limit: 20)
```

Search entities by name.

**Parameters:**

- `query` (String) - Search query
- `type` (Symbol) - Optional type filter
- `limit` (Integer) - Max results

**Returns:** `Array<Models::Entity>`

---

### by_type

```ruby
def by_type(type)
```

Filter entities by type.

**Returns:** `ActiveRecord::Relation`

---

### in_source

```ruby
def in_source(source_id)
```

Find entities mentioned in a source.

**Returns:** `Array<Models::Entity>`

---

### related_to

```ruby
def related_to(entity_id)
```

Find entities that appear in facts with the given entity.

**Returns:** `Array<Models::Entity>`

---

### semantic_search

```ruby
def semantic_search(query, type: nil, limit: 10)
```

Semantic similarity search using embeddings.

**Returns:** `Array<Models::Entity>`
