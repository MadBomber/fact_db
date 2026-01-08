# HR Onboarding Example

Track employee lifecycle events - hiring, promotions, transfers, and departures.

## Scenario

An HR system that tracks employee facts over time, maintaining a complete audit trail of employment events.

## Setup

```ruby
require 'fact_db'

FactDb.configure do |config|
  config.database_url = ENV['DATABASE_URL']
  config.llm_provider = :openai
  config.llm_api_key = ENV['OPENAI_API_KEY']
end

facts = FactDb.new
```

## Create Organization Structure

```ruby
# Company
acme = facts.entity_service.create(
  "Acme Corporation",
  type: :organization,
  aliases: ["Acme", "Acme Corp"]
)

# Departments
engineering = facts.entity_service.create(
  "Engineering Department",
  type: :organization,
  aliases: ["Engineering", "Eng"]
)

sales = facts.entity_service.create(
  "Sales Department",
  type: :organization,
  aliases: ["Sales"]
)

# Locations
hq = facts.entity_service.create(
  "Headquarters",
  type: :place,
  aliases: ["HQ", "Main Office"],
  metadata: { address: "123 Main St, San Francisco, CA" }
)
```

## Track Hiring Event

```ruby
# Ingest offer letter
offer_letter = facts.ingest(
  <<~TEXT,
    Dear Paula Chen,

    We are pleased to offer you the position of Software Engineer
    at Acme Corporation, starting March 1, 2022.

    Your starting salary will be $120,000 per year.
    You will report to John Smith, Engineering Manager.

    Location: Headquarters, San Francisco
  TEXT
  type: :document,
  title: "Offer Letter - Paula Chen",
  captured_at: Date.parse("2022-02-15")
)

# Create employee
paula = facts.entity_service.create(
  "Paula Chen",
  type: :person,
  aliases: ["Paula"],
  metadata: { employee_id: "E001" }
)

john = facts.entity_service.create(
  "John Smith",
  type: :person,
  aliases: ["John"],
  metadata: { employee_id: "M001" }
)

# Create employment facts
facts.fact_service.create(
  "Paula Chen is employed at Acme Corporation",
  valid_at: Date.parse("2022-03-01"),
  mentions: [
    { entity: paula, role: "subject", text: "Paula Chen" },
    { entity: acme, role: "organization", text: "Acme Corporation" }
  ],
  sources: [{ content: offer_letter, type: "primary" }]
)

facts.fact_service.create(
  "Paula Chen's title is Software Engineer",
  valid_at: Date.parse("2022-03-01"),
  mentions: [{ entity: paula, role: "subject", text: "Paula Chen" }],
  sources: [{ content: offer_letter, type: "primary" }]
)

facts.fact_service.create(
  "Paula Chen reports to John Smith",
  valid_at: Date.parse("2022-03-01"),
  mentions: [
    { entity: paula, role: "subject", text: "Paula Chen" },
    { entity: john, role: "object", text: "John Smith" }
  ],
  sources: [{ content: offer_letter, type: "primary" }]
)

facts.fact_service.create(
  "Paula Chen works in Engineering Department",
  valid_at: Date.parse("2022-03-01"),
  mentions: [
    { entity: paula, role: "subject", text: "Paula Chen" },
    { entity: engineering, role: "organization", text: "Engineering" }
  ],
  sources: [{ content: offer_letter, type: "primary" }]
)
```

## Track Promotion

```ruby
# Ingest promotion letter
promotion = facts.ingest(
  <<~TEXT,
    Dear Paula,

    Congratulations! Effective January 15, 2023, you have been
    promoted to Senior Software Engineer.

    Your new salary will be $145,000 per year.
  TEXT
  type: :document,
  title: "Promotion Letter - Paula Chen",
  captured_at: Date.parse("2023-01-10")
)

# Supersede title fact
title_fact = FactDb::Models::Fact
  .mentioning_entity(paula.id)
  .search_text("title")
  .canonical
  .first

facts.fact_service.resolver.supersede(
  title_fact.id,
  "Paula Chen's title is Senior Software Engineer",
  valid_at: Date.parse("2023-01-15")
)
```

## Track Transfer

```ruby
# Ingest transfer notice
transfer = facts.ingest(
  <<~TEXT,
    Effective July 1, 2023, Paula Chen will transfer from
    Engineering to Sales as Sales Engineer, reporting to
    Maria Garcia.
  TEXT
  type: :document,
  title: "Transfer Notice - Paula Chen",
  captured_at: Date.parse("2023-06-15")
)

maria = facts.entity_service.create(
  "Maria Garcia",
  type: :person,
  metadata: { employee_id: "M002" }
)

# Supersede department fact
dept_fact = FactDb::Models::Fact
  .mentioning_entity(paula.id)
  .search_text("Department")
  .canonical
  .first

facts.fact_service.resolver.supersede(
  dept_fact.id,
  "Paula Chen works in Sales Department",
  valid_at: Date.parse("2023-07-01")
)

# Supersede manager fact
manager_fact = FactDb::Models::Fact
  .mentioning_entity(paula.id)
  .search_text("reports to")
  .canonical
  .first

facts.fact_service.resolver.supersede(
  manager_fact.id,
  "Paula Chen reports to Maria Garcia",
  valid_at: Date.parse("2023-07-01")
)

# Supersede title
title_fact = FactDb::Models::Fact
  .mentioning_entity(paula.id)
  .search_text("title")
  .canonical
  .first

facts.fact_service.resolver.supersede(
  title_fact.id,
  "Paula Chen's title is Sales Engineer",
  valid_at: Date.parse("2023-07-01")
)
```

## Query Employment History

```ruby
# Complete timeline
puts "Paula Chen's Employment Timeline:"
puts "=" * 50

facts.timeline_for(paula.id).each do |fact|
  valid = fact.invalid_at ?
    "#{fact.valid_at.to_date} - #{fact.invalid_at.to_date}" :
    "#{fact.valid_at.to_date} - present"

  status = fact.superseded? ? " [superseded]" : ""
  puts "#{valid}: #{fact.fact_text}#{status}"
end
```

Output:
```
Paula Chen's Employment Timeline:
==================================================
2022-03-01 - present: Paula Chen is employed at Acme Corporation
2022-03-01 - 2023-01-15: Paula Chen's title is Software Engineer [superseded]
2023-01-15 - 2023-07-01: Paula Chen's title is Senior Software Engineer [superseded]
2023-07-01 - present: Paula Chen's title is Sales Engineer
2022-03-01 - 2023-07-01: Paula Chen works in Engineering Department [superseded]
2023-07-01 - present: Paula Chen works in Sales Department
2022-03-01 - 2023-07-01: Paula Chen reports to John Smith [superseded]
2023-07-01 - present: Paula Chen reports to Maria Garcia
```

## Point-in-Time Queries

```ruby
# What was Paula's status on different dates?

dates = [
  Date.parse("2022-06-01"),
  Date.parse("2023-03-01"),
  Date.parse("2023-10-01")
]

dates.each do |date|
  puts "\nPaula's status on #{date}:"
  facts.facts_at(date, entity: paula.id).each do |fact|
    puts "  - #{fact.fact_text}"
  end
end
```

## Generate Employment Report

```ruby
def employment_report(facts, employee_id)
  employee = FactDb::Models::Entity.find(employee_id)
  current = facts.current_facts_for(employee_id)

  report = {
    name: employee.canonical_name,
    current_status: {},
    history: []
  }

  # Current status
  current.each do |fact|
    if fact.fact_text.include?("title is")
      report[:current_status][:title] = fact.fact_text.split("title is ").last
    elsif fact.fact_text.include?("works in")
      report[:current_status][:department] = fact.fact_text.split("works in ").last
    elsif fact.fact_text.include?("reports to")
      report[:current_status][:manager] = fact.fact_text.split("reports to ").last
    end
  end

  # Employment history
  report[:history] = facts.timeline_for(employee_id).map do |fact|
    {
      fact: fact.fact_text,
      from: fact.valid_at,
      to: fact.invalid_at,
      status: fact.status
    }
  end

  report
end

report = employment_report(facts, paula.id)
puts JSON.pretty_generate(report)
```
