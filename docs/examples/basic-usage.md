# Basic Usage

A simple introduction to FactDb's core functionality.

## Setup

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
```

## Ingest Content

```ruby
# Ingest an email
email = facts.ingest(
  <<~TEXT,
    Hi team,

    I'm excited to announce that Paula Chen has accepted our offer
    to join Microsoft as Principal Engineer starting January 10, 2024.

    She'll be part of the Platform team reporting to Sarah Johnson.

    Best,
    HR
  TEXT
  type: :email,
  title: "New Hire Announcement - Paula Chen",
  captured_at: Time.current
)

puts "Ingested content ID: #{email.id}"
```

## Create Entities

```ruby
# Create people
paula = facts.entity_service.create(
  "Paula Chen",
  type: :person,
  aliases: ["Paula"]
)

sarah = facts.entity_service.create(
  "Sarah Johnson",
  type: :person,
  aliases: ["Sarah"]
)

# Create organization
microsoft = facts.entity_service.create(
  "Microsoft",
  type: :organization,
  aliases: ["MS", "MSFT"]
)

platform_team = facts.entity_service.create(
  "Platform Team",
  type: :organization
)

puts "Created entities: Paula, Sarah, Microsoft, Platform Team"
```

## Extract Facts Manually

```ruby
# Create facts with explicit links
fact1 = facts.fact_service.create(
  "Paula Chen joined Microsoft as Principal Engineer",
  valid_at: Date.parse("2024-01-10"),
  mentions: [
    { entity: paula, role: "subject", text: "Paula Chen" },
    { entity: microsoft, role: "organization", text: "Microsoft" }
  ],
  sources: [
    { source: email, type: "primary" }
  ]
)

fact2 = facts.fact_service.create(
  "Paula Chen reports to Sarah Johnson",
  valid_at: Date.parse("2024-01-10"),
  mentions: [
    { entity: paula, role: "subject", text: "Paula Chen" },
    { entity: sarah, role: "object", text: "Sarah Johnson" }
  ],
  sources: [
    { source: email, type: "primary" }
  ]
)

fact3 = facts.fact_service.create(
  "Paula Chen is on the Platform Team",
  valid_at: Date.parse("2024-01-10"),
  mentions: [
    { entity: paula, role: "subject", text: "Paula Chen" },
    { entity: platform_team, role: "organization", text: "Platform Team" }
  ],
  sources: [
    { source: email, type: "primary" }
  ]
)

puts "Created #{3} facts"
```

## Extract Facts with LLM

```ruby
# Alternative: let LLM extract facts
extracted = facts.extract_facts(email.id, extractor: :llm)

puts "LLM extracted #{extracted.count} facts:"
extracted.each do |fact|
  puts "  - #{fact.fact_text}"
end
```

## Query Facts

```ruby
# Current facts about Paula
puts "\nCurrent facts about Paula:"
facts.current_facts_for(paula.id).each do |fact|
  puts "  - #{fact.fact_text}"
end

# Facts about Microsoft
puts "\nFacts about Microsoft:"
facts.query_facts(entity: microsoft.id).each do |fact|
  puts "  - #{fact.fact_text}"
end
```

## Resolve Entity

```ruby
# Resolve a name
resolved = facts.resolve_entity("Paula")
puts "\n'Paula' resolves to: #{resolved&.canonical_name}"

# Type-constrained resolution
person = facts.resolve_entity("Paula", type: :person)
puts "'Paula' as person: #{person&.canonical_name}"
```

## Update Facts (Supersession)

```ruby
# Paula gets promoted
new_fact = facts.fact_service.resolver.supersede(
  fact1.id,
  "Paula Chen is Senior Principal Engineer at Microsoft",
  valid_at: Date.parse("2024-06-01")
)

puts "\nSuperseded fact:"
puts "  Old: #{fact1.reload.fact_text} (#{fact1.status})"
puts "  New: #{new_fact.fact_text} (#{new_fact.status})"
```

## Timeline

```ruby
# Build timeline
puts "\nPaula's timeline:"
facts.timeline_for(paula.id).each do |fact|
  valid = fact.invalid_at ? "#{fact.valid_at} - #{fact.invalid_at}" : "#{fact.valid_at} - present"
  puts "  #{valid}: #{fact.fact_text}"
end
```

## Historical Query

```ruby
# What did we know before promotion?
puts "\nFacts about Paula on March 1, 2024:"
facts.facts_at(Date.parse("2024-03-01"), entity: paula.id).each do |fact|
  puts "  - #{fact.fact_text}"
end

# What do we know after promotion?
puts "\nFacts about Paula on July 1, 2024:"
facts.facts_at(Date.parse("2024-07-01"), entity: paula.id).each do |fact|
  puts "  - #{fact.fact_text}"
end
```

## Complete Script

```ruby
#!/usr/bin/env ruby
require 'fact_db'

# Setup
FactDb.configure do |config|
  config.database.url = ENV['DATABASE_URL'] || 'postgresql://localhost/fact_db'
end

facts = FactDb.new

# Ingest
source = facts.ingest("Paula joined Microsoft on Jan 10, 2024", type: :note)

# Create entities
paula = facts.entity_service.create("Paula", type: :person)
microsoft = facts.entity_service.create("Microsoft", type: :organization)

# Create fact
fact = facts.fact_service.create(
  "Paula joined Microsoft",
  valid_at: Date.parse("2024-01-10"),
  mentions: [
    { entity: paula, role: "subject", text: "Paula" },
    { entity: microsoft, role: "organization", text: "Microsoft" }
  ],
  sources: [{ source: source, type: "primary" }]
)

# Query
puts "Current facts about Paula:"
facts.current_facts_for(paula.id).each { |f| puts "  - #{f.fact_text}" }
```
