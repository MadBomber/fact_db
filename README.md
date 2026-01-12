# FactDb

> [!CAUTION]
> This gem is under active development. APIs and features may change without notice. See the [CHANGELOG](CHANGELOG.md) for details.

<table>
<tr>
<td width="50%" align="center" valign="top">
<img src="docs/assets/fact_db.jpg" alt="FactDb"><br>
<em>"Do you swear to add the facts and only the facts?"</em>
</td>
<td width="50%" valign="top">
<strong>Temporal fact tracking with entity resolution and audit trails for Ruby</strong><br><br>
FactDb implements the Event Clock concept - capturing organizational knowledge through temporal facts with validity periods (<code>valid_at</code>/<code>invalid_at</code>), entity resolution, and audit trails back to source content.<br><br>
<strong>Key Features</strong><br>
    
- <strong>Temporal Facts</strong> - Track facts with validity periods<br>
- <strong>Entity Resolution</strong> - Resolve mentions to canonical entities<br>
- <strong>Audit Trails</strong> - Every fact links back to source content<br>
- <strong>Multiple Extractors</strong> - Extract facts manually, via LLM, or rule-based<br>
- <strong>Semantic Search</strong> - PostgreSQL with pgvector<br>
- <strong>Concurrent Processing</strong> - Batch process with parallel pipelines<br>
- <strong>Output Formats</strong> - JSON, triples, Cypher, or text for LLM consumption<br>
- <strong>Temporal Queries</strong> - Fluent API for point-in-time queries and diffs
</td>
</tr>
</table>

## Installation

Add to your Gemfile:

```ruby
gem 'fact_db'
```

Then run:

```bash
bundle install
```

### Requirements

- Ruby >= 3.0
- PostgreSQL with pgvector extension
- Optional: ruby_llm gem for LLM-powered extraction

## Getting Started

```ruby
require 'fact_db'

# Configure with a PostgreSQL database URL
# If you want to use an envar name different from the standard
# FDB_DATABASE__URL then you must set the config.database.url in code ...
FactDb.configure do |config|
  config.database.url = ENV["YOUR_DATABASE_URL_ENVAR_NAME"]
end

# Run migrations to create the schema (only needed once)
FactDb::Database.migrate!

# Create a facts instance
facts = FactDb.new
```

Configuration uses nested sections. You can also use environment variables:

```bash
export FDB_DATABASE__URL="postgresql://localhost/fact_db"
export FDB_LLM__PROVIDER="openai"
export FDB_LLM__API_KEY="sk-..."
```

Once configured, you can ingest content and create facts:

```ruby
# Ingest content
content = facts.ingest(
  "Paula Chen joined Microsoft as Principal Engineer on January 10, 2024.",
  type: :email,
  captured_at: Time.now
)

# Create entities
paula = facts.entity_service.create("Paula Chen", type: :person)
microsoft = facts.entity_service.create("Microsoft", type: :organization)

# Create a fact with entity mentions
facts.fact_service.create(
  "Paula Chen is Principal Engineer at Microsoft",
  valid_at: Date.new(2024, 1, 10),
  mentions: [
    { entity_id: paula.id, role: :subject, text: "Paula Chen" },
    { entity_id: microsoft.id, role: :object, text: "Microsoft" }
  ]
)
```

Query facts temporally:

```ruby
# Query current facts about Paula
facts.current_facts_for(paula.id).each do |fact|
  puts fact.text
end

# Query facts at a point in time (before she joined)
facts.facts_at(Date.new(2023, 6, 15), entity: paula.id)
```

## Output Formats

Query results can be transformed into multiple formats for different use cases:

```ruby
# Raw - original ActiveRecord objects for direct database access
results = facts.query_facts(topic: "Paula Chen", format: :raw)
results.each do |fact|
  puts fact.text
  puts fact.entity_mentions.map(&:entity).map(&:name)
end

# JSON (default) - structured hash
facts.query_facts(topic: "Paula Chen", format: :json)

# Triples - Subject-Predicate-Object for semantic encoding
facts.query_facts(topic: "Paula Chen", format: :triples)
# => [["Paula Chen", "type", "Person"],
#     ["Paula Chen", "works_at", "Microsoft"],
#     ["Paula Chen", "works_at.valid_from", "2024-01-10"]]

# Cypher - graph notation with nodes and relationships
facts.query_facts(topic: "Paula Chen", format: :cypher)
# => (paula_chen:Person {name: "Paula Chen"})
#    (microsoft:Organization {name: "Microsoft"})
#    (paula_chen)-[:WORKS_AT {since: "2024-01-10"}]->(microsoft)

# Text - human-readable markdown
facts.query_facts(topic: "Paula Chen", format: :text)
```

## Temporal Query Builder

Use the fluent API for point-in-time queries:

```ruby
# Query at a specific date
facts.at("2024-01-15").query("Paula's role", format: :cypher)

# Get all facts valid at a date
facts.at("2024-01-15").facts

# Get facts for a specific entity at that date
facts.at("2024-01-15").facts_for(paula.id)

# Compare what changed between two dates
facts.at("2024-01-15").compare_to("2024-06-15")
```

## Comparing Changes Over Time

Track what changed between two points in time:

```ruby
diff = facts.diff("Paula Chen", from: "2024-01-01", to: "2024-06-01")

diff[:added]     # Facts that became valid
diff[:removed]   # Facts that were superseded
diff[:unchanged] # Facts that remained valid
```

## Introspection

Discover what the fact database knows about:

```ruby
# Get schema and capabilities
facts.introspect
# => { capabilities: [:temporal_query, :entity_resolution, ...],
#      entity_types: ["person", "organization", ...],
#      output_formats: [:raw, :json, :triples, :cypher, :text],
#      statistics: { facts: {...}, entities: {...} } }

# Get coverage for a specific topic
facts.introspect("Paula Chen")
# => { entity: {...}, coverage: {...}, relationships: [...],
#      suggested_queries: ["current status", "employment history"] }

# Get query suggestions
facts.suggest_queries("Paula Chen")
# => ["current status", "employment history", "timeline"]

# Get retrieval strategy recommendations
facts.suggest_strategies("What happened last week?")
# => [{ strategy: :temporal, description: "Filter by date range" }]
```

## Documentation

Full documentation is available at **[https://madbomber.github.io/fact_db](https://madbomber.github.io/fact_db)**

## Examples

See the [examples directory](examples/README.md) for runnable demo programs covering:

- Basic usage and fact creation
- Entity management and resolution
- Temporal queries and timelines
- Rule-based fact extraction
- A complete HR system example

## License

MIT License - Copyright (c) 2025 Dewayne VanHoozer
