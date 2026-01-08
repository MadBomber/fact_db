# FactDb

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
- <strong>Concurrent Processing</strong> - Batch process with parallel pipelines
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

# Configure
FactDb.configure do |config|
  config.database_url = ENV['DATABASE_URL']
end

# Create a facts instance
facts = FactDb.new

# Ingest content
content = facts.ingest(
  "Paula Chen joined Microsoft as Principal Engineer on January 10, 2024.",
  type: :email,
  captured_at: Time.current
)

# Create entities
paula = facts.entity_service.create("Paula Chen", type: :person)

# Create a fact
facts.fact_service.create(
  "Paula Chen is Principal Engineer at Microsoft",
  valid_at: Date.new(2024, 1, 10),
  mentions: [{ entity_id: paula.id, role: :subject, text: "Paula Chen" }]
)

# Query current facts
facts.current_facts_for(paula.id).each do |fact|
  puts fact.fact_text
end

# Query facts at a point in time
facts.facts_at(Date.new(2023, 6, 15), entity: paula.id)
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
