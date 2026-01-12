#!/usr/bin/env ruby
# frozen_string_literal: true

# Fluent Temporal API Example for FactDb
#
# This example demonstrates:
# - The new fluent query builder API: facts.at(date).query(...)
# - Comparing facts between two dates with diff()
# - Point-in-time queries with chaining
# - Getting entity state at specific moments

require_relative "utilities"

demo_setup!("FactDb Fluent Temporal API Demo")
demo_configure_logging(__FILE__)

facts = FactDb.new
entity_service = facts.entity_service
fact_service = facts.fact_service

demo_section("Setup: Creating Career Progression Data")

# Create entities
alex = entity_service.resolve_or_create(
  "Alex Rivera",
  kind: :person,
  description: "Software professional"
)

startup = entity_service.resolve_or_create(
  "TechStartup Inc",
  kind: :organization,
  description: "Early stage company"
)

bigcorp = entity_service.resolve_or_create(
  "BigCorp Systems",
  kind: :organization,
  description: "Enterprise software company"
)

sf = entity_service.resolve_or_create(
  "San Francisco",
  kind: :place
)

nyc = entity_service.resolve_or_create(
  "New York City",
  kind: :place
)

puts "Created entities for Alex's career story"

# Create temporal facts showing career progression
# 2020: Alex joins TechStartup as Junior Developer
fact_service.find_or_create(
  "Alex Rivera is Junior Developer at TechStartup Inc",
  valid_at: Date.new(2020, 3, 1),
  invalid_at: Date.new(2022, 6, 30),
  extraction_method: :manual,
  mentions: [
    { entity_id: alex.id, role: :subject, text: "Alex Rivera" },
    { entity_id: startup.id, role: :object, text: "TechStartup Inc" }
  ]
)

fact_service.find_or_create(
  "Alex Rivera works at San Francisco office",
  valid_at: Date.new(2020, 3, 1),
  invalid_at: Date.new(2023, 8, 31),
  extraction_method: :manual,
  mentions: [
    { entity_id: alex.id, role: :subject, text: "Alex Rivera" },
    { entity_id: sf.id, role: :location, text: "San Francisco" }
  ]
)

# 2022: Promoted to Senior Developer
fact_service.find_or_create(
  "Alex Rivera is Senior Developer at TechStartup Inc",
  valid_at: Date.new(2022, 7, 1),
  invalid_at: Date.new(2023, 8, 31),
  extraction_method: :manual,
  mentions: [
    { entity_id: alex.id, role: :subject, text: "Alex Rivera" },
    { entity_id: startup.id, role: :object, text: "TechStartup Inc" }
  ]
)

# 2023: Moves to BigCorp
fact_service.find_or_create(
  "Alex Rivera is Principal Engineer at BigCorp Systems",
  valid_at: Date.new(2023, 9, 1),
  extraction_method: :manual,
  mentions: [
    { entity_id: alex.id, role: :subject, text: "Alex Rivera" },
    { entity_id: bigcorp.id, role: :object, text: "BigCorp Systems" }
  ]
)

fact_service.find_or_create(
  "Alex Rivera works at New York City office",
  valid_at: Date.new(2023, 9, 1),
  extraction_method: :manual,
  mentions: [
    { entity_id: alex.id, role: :subject, text: "Alex Rivera" },
    { entity_id: nyc.id, role: :location, text: "New York City" }
  ]
)

puts "Created career progression facts (2020-2024)"

demo_section("Section 1: Fluent Query Builder - Basic Usage")

puts "\nQuery: What was Alex's role in 2021?"
results_2021 = facts.at("2021-06-15").facts_for(alex.id)
puts "Date: 2021-06-15"
results_2021.each_fact do |fact|
  puts "  - #{fact[:text]}"
end

puts "\nQuery: What was Alex's role in 2022 (after promotion)?"
results_2022 = facts.at("2022-09-01").facts_for(alex.id)
puts "Date: 2022-09-01"
results_2022.each_fact do |fact|
  puts "  - #{fact[:text]}"
end

puts "\nQuery: What is Alex's current situation?"
results_now = facts.at(Date.today).facts_for(alex.id)
puts "Date: #{Date.today}"
results_now.each_fact do |fact|
  puts "  - #{fact[:text]}"
end

demo_section("Section 2: Query Builder with Output Formats")

puts "\nAlex's 2023 state as Cypher graph:"
cypher_2023 = facts.at("2023-10-01").facts_for(alex.id, format: :cypher)
puts cypher_2023

puts "\nAlex's 2023 state as Triples:"
triples_2023 = facts.at("2023-10-01").facts_for(alex.id, format: :triples)
triples_2023.each { |t| puts "  #{t.inspect}" }

demo_section("Section 3: Comparing Two Points in Time")

puts "\nComparing Alex's situation: 2021-06-01 vs 2024-01-01"
diff_result = facts.diff(nil, from: "2021-06-01", to: "2024-01-01")

puts "\nRemoved facts (no longer true):"
diff_result[:removed].each do |fact|
  puts "  - #{fact.text}"
end

puts "\nAdded facts (became true):"
diff_result[:added].each do |fact|
  puts "  - #{fact.text}"
end

puts "\nUnchanged facts:"
if diff_result[:unchanged].empty?
  puts "  (none - everything changed!)"
else
  diff_result[:unchanged].each do |fact|
    puts "  - #{fact.text}"
  end
end

demo_section("Section 4: Query Builder - Compare To")

puts "\nUsing fluent API to compare dates:"
comparison = facts.at("2020-06-01").compare_to("2023-10-01")

puts "\nFrom #{comparison[:from]} to #{comparison[:to]}:"
puts "  Added: #{comparison[:added].count} facts"
puts "  Removed: #{comparison[:removed].count} facts"
puts "  Unchanged: #{comparison[:unchanged].count} facts"

demo_section("Section 5: Career Timeline View")

checkpoints = [
  Date.new(2020, 6, 1),
  Date.new(2021, 6, 1),
  Date.new(2022, 6, 1),
  Date.new(2022, 8, 1),
  Date.new(2023, 6, 1),
  Date.new(2023, 10, 1),
  Date.new(2024, 1, 1)
]

puts "\nAlex Rivera's Career Timeline:\n"
checkpoints.each do |date|
  snapshot = facts.at(date).facts_for(alex.id, format: :text)
  fact_count = facts.at(date).facts_for(alex.id).fact_count

  puts "#{date.strftime('%Y-%m-%d')} (#{fact_count} facts):"
  if fact_count.zero?
    puts "  (no facts yet)"
  else
    facts.at(date).facts_for(alex.id).each_fact do |fact|
      puts "  - #{fact[:text]}"
    end
  end
  puts
end

demo_section("Section 6: State For - Entity State at a Date")

puts "\nSnapshot of Alex's state on 2022-08-01:"
state = facts.at("2022-08-01").state_for(alex.id)
puts "Facts at this moment:"
state.each_fact do |fact|
  puts "  - #{fact[:text]}"
end

demo_footer
