# Quick Start

Get FactDb running in 5 minutes.

## 1. Configure

Create a configuration file or use environment variables:

=== "Environment Variables"

    ```bash
    export FDB_DATABASE__URL="postgresql://localhost/fact_db"
    export FDB_LLM__PROVIDER="openai"
    export FDB_LLM__API_KEY="sk-..."
    ```

=== "YAML Config"

    ```yaml
    # config/fact_db.yml
    database:
      url: postgresql://localhost/fact_db

    llm:
      provider: openai
      api_key: <%= ENV['OPENAI_API_KEY'] %>
    ```

=== "Ruby Block"

    ```ruby
    FactDb.configure do |config|
      config.database.url = "postgresql://localhost/fact_db"
      config.llm.provider = :openai
      config.llm.api_key = ENV['OPENAI_API_KEY']
    end
    ```

## 2. Set Up Database

Run the migrations:

```ruby
require 'fact_db'

FactDb.configure do |config|
  config.database.url = ENV['DATABASE_URL']
end

# Run migrations
FactDb::Database.migrate!
```

## 3. Create Your First Facts Instance

```ruby
require 'fact_db'

facts = FactDb.new
```

## 4. Ingest Content

```ruby
# Ingest an email
content = facts.ingest(
  "Hi team, Paula Chen has accepted our offer and will join as Principal Engineer starting January 10, 2024. She'll be reporting to Sarah in the Platform team.",
  type: :email,
  title: "New Hire Announcement",
  captured_at: Time.current
)

puts "Ingested content: #{content.id}"
```

## 5. Create Entities

```ruby
# Create entities for people and organizations
paula = facts.entity_service.create(
  "Paula Chen",
  type: :person,
  aliases: ["Paula", "P. Chen"]
)

sarah = facts.entity_service.create(
  "Sarah Johnson",
  type: :person,
  aliases: ["Sarah"]
)

platform_team = facts.entity_service.create(
  "Platform Team",
  type: :organization
)
```

## 6. Extract Facts

### Manual Extraction

```ruby
fact = facts.fact_service.create(
  "Paula Chen joined as Principal Engineer",
  valid_at: Date.parse("2024-01-10"),
  mentions: [
    { entity: paula, role: "subject", text: "Paula Chen" }
  ],
  sources: [
    { content: content, type: "primary" }
  ]
)
```

### LLM Extraction

```ruby
# Extract facts automatically using LLM
extracted = facts.extract_facts(content.id, extractor: :llm)

extracted.each do |fact|
  puts "Extracted: #{fact.fact_text}"
  puts "  Valid from: #{fact.valid_at}"
end
```

## 7. Query Facts

```ruby
# Get current facts about Paula
current = facts.current_facts_for(paula.id)
current.each { |f| puts f.fact_text }

# Get facts valid at a specific date
historical = facts.facts_at(
  Date.parse("2023-12-01"),
  entity: paula.id
)

# Search by topic
team_facts = facts.query_facts(topic: "Platform Team")
```

## 8. Build Timelines

```ruby
timeline = facts.timeline_for(paula.id)

timeline.each do |entry|
  puts "#{entry[:date]}: #{entry[:fact].fact_text}"
end
```

## Complete Example

```ruby
require 'fact_db'

# Configure
FactDb.configure do |config|
  config.database.url = ENV['DATABASE_URL']
  config.llm.provider = :openai
  config.llm.api_key = ENV['OPENAI_API_KEY']
end

# Create facts instance
facts = FactDb.new

# Ingest content
content = facts.ingest(
  "Paula Chen joined Microsoft as Principal Engineer on January 10, 2024.",
  type: :announcement,
  captured_at: Time.current
)

# Create entities
paula = facts.entity_service.create("Paula Chen", type: :person)
microsoft = facts.entity_service.create("Microsoft", type: :organization)

# Extract facts via LLM
extracted = facts.extract_facts(content.id, extractor: :llm)

# Query
puts "Current facts about Paula:"
facts.current_facts_for(paula.id).each do |fact|
  puts "  - #{fact.fact_text}"
end
```

## Next Steps

- [Configuration Guide](../guides/configuration.md) - Detailed configuration options
- [Ingesting Content](../guides/ingesting-content.md) - Learn about content types
- [LLM Integration](../guides/llm-integration.md) - Set up LLM providers
