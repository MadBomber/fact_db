#!/usr/bin/env ruby
# frozen_string_literal: true

# Temporal Queries Example for FactDb
#
# This example demonstrates:
# - Creating facts with temporal bounds
# - Querying facts at specific points in time
# - Superseding facts (replacing old with new)
# - Detecting fact changes over time
# - Building temporal diffs

require_relative "utilities"

demo_setup!("FactDb Temporal Queries Demo")
demo_configure_logging(__FILE__)

facts = FactDb.new
entity_service = facts.entity_service
fact_service = facts.fact_service

demo_section("Setup: Creating Entities")

company = entity_service.create(
  "TechCorp Ltd",
  type: :organization,
  description: "Technology company"
)

ceo = entity_service.create(
  "Alice Chen",
  type: :person,
  description: "Executive"
)

new_ceo = entity_service.create(
  "David Park",
  type: :person,
  description: "Executive"
)

cfo = entity_service.create(
  "Sarah Miller",
  type: :person,
  description: "Finance executive"
)

puts "Created entities: #{company.name}, #{ceo.name}, #{new_ceo.name}, #{cfo.name}"

demo_section("Section 1: Creating Temporal Facts")

# Fact with open-ended validity (still true)
fact1 = fact_service.create(
  "TechCorp Ltd is headquartered in Austin, Texas",
  valid_at: Date.new(2015, 1, 1),
  mentions: [{ entity_id: company.id, role: :subject, text: "TechCorp Ltd" }]
)
puts "Created: #{fact1.text}"
puts "  Valid: #{fact1.valid_at} - present"

# Fact with closed validity (historical)
fact2 = fact_service.create(
  "Alice Chen is CEO of TechCorp Ltd",
  valid_at: Date.new(2018, 3, 1),
  invalid_at: Date.new(2024, 12, 31),
  mentions: [
    { entity_id: ceo.id, role: :subject, text: "Alice Chen" },
    { entity_id: company.id, role: :object, text: "TechCorp Ltd" }
  ]
)
puts "\nCreated: #{fact2.text}"
puts "  Valid: #{fact2.valid_at} - #{fact2.invalid_at}"

# Current CEO
fact3 = fact_service.create(
  "David Park is CEO of TechCorp Ltd",
  valid_at: Date.new(2025, 1, 1),
  mentions: [
    { entity_id: new_ceo.id, role: :subject, text: "David Park" },
    { entity_id: company.id, role: :object, text: "TechCorp Ltd" }
  ]
)
puts "\nCreated: #{fact3.text}"
puts "  Valid: #{fact3.valid_at} - present"

# Another current fact
fact4 = fact_service.create(
  "Sarah Miller is CFO of TechCorp Ltd",
  valid_at: Date.new(2020, 6, 15),
  mentions: [
    { entity_id: cfo.id, role: :subject, text: "Sarah Miller" },
    { entity_id: company.id, role: :object, text: "TechCorp Ltd" }
  ]
)
puts "\nCreated: #{fact4.text}"
puts "  Valid: #{fact4.valid_at} - present"

demo_section("Section 2: Point-in-Time Queries")

# Query facts valid at different dates
dates_to_query = [
  Date.new(2019, 6, 1),  # Alice was CEO
  Date.new(2024, 6, 1),  # Alice still CEO
  Date.new(2025, 6, 1),  # David is CEO
  Date.today
]

dates_to_query.each do |date|
  puts "\nFacts about TechCorp on #{date}:"
  facts = fact_service.facts_at(date, entity: company.id)
  facts.each do |fact|
    puts "  - #{fact.text}"
  end
end

demo_section("Section 3: Current vs Historical Facts")

puts "Currently valid facts about TechCorp:"
current = fact_service.current_facts(entity: company.id)
current.each { |f| puts "  - #{f.text}" }

puts "\nAll historical facts:"
FactDb::Models::Fact.historical.each do |fact|
  puts "  - #{fact.text} (ended: #{fact.invalid_at})"
end

demo_section("Section 4: Superseding Facts")

# Company valuation that changes over time
valuation_2020 = fact_service.create(
  "TechCorp Ltd has a market valuation of $500 million",
  valid_at: Date.new(2020, 1, 1),
  mentions: [{ entity_id: company.id, role: :subject, text: "TechCorp Ltd" }]
)
puts "Created valuation fact: #{valuation_2020.text}"

# Supersede with new valuation
valuation_2023 = fact_service.supersede(
  valuation_2020.id,
  "TechCorp Ltd has a market valuation of $1.2 billion",
  valid_at: Date.new(2023, 1, 1),
  mentions: [{ entity_id: company.id, role: :subject, text: "TechCorp Ltd" }]
)
puts "\nSuperseded with: #{valuation_2023.text}"

# Check the old fact status
valuation_2020.reload
puts "\nOriginal fact status: #{valuation_2020.status}"
puts "Original fact now invalid at: #{valuation_2020.invalid_at}"

demo_section("Section 5: Temporal Timeline")

timeline = fact_service.timeline(
  entity_id: company.id,
  from: Date.new(2015, 1, 1),
  to: Date.today
)

puts "Complete timeline for #{company.name}:"
timeline.each do |entry|
  end_date = entry[:invalid_at] || "present"
  status_indicator = entry[:status] == "canonical" ? "" : " [#{entry[:status]}]"
  puts "  #{entry[:valid_at]} - #{end_date}: #{entry[:text]}#{status_indicator}"
end

demo_section("Section 6: Temporal Diff")

temporal_query = FactDb::Temporal::Query.new

# Compare company facts between two dates
puts "Changes to TechCorp facts between 2020-01-01 and 2025-06-01:"
diff = temporal_query.diff(
  entity_id: company.id,
  from_date: Date.new(2020, 1, 1),
  to_date: Date.new(2025, 6, 1)
)

if diff[:added].any?
  puts "\n  Added:"
  diff[:added].each { |f| puts "    + #{f.text}" }
end

if diff[:removed].any?
  puts "\n  Removed:"
  diff[:removed].each { |f| puts "    - #{f.text}" }
end

if diff[:unchanged].any?
  puts "\n  Unchanged:"
  diff[:unchanged].each { |f| puts "    = #{f.text}" }
end

demo_section("Section 7: Facts Created/Invalidated in Date Range")

puts "Facts that became valid in 2025:"
new_facts = temporal_query.facts_created_between(
  from: Date.new(2025, 1, 1),
  to: Date.new(2025, 12, 31)
)
new_facts.each { |f| puts "  - #{f.text} (valid from #{f.valid_at})" }

puts "\nFacts that ended in 2024:"
ended_facts = temporal_query.facts_invalidated_between(
  from: Date.new(2024, 1, 1),
  to: Date.new(2024, 12, 31)
)
ended_facts.each { |f| puts "  - #{f.text} (ended #{f.invalid_at})" }

demo_section("Section 8: Entity Role Queries")

puts "Facts where TechCorp is the subject:"
subject_facts = temporal_query.facts_with_entity_role(
  entity_id: company.id,
  role: :subject
)
subject_facts.each { |f| puts "  - #{f.text}" }

puts "\nFacts where TechCorp is the object:"
object_facts = temporal_query.facts_with_entity_role(
  entity_id: company.id,
  role: :object
)
object_facts.each { |f| puts "  - #{f.text}" }

demo_footer
