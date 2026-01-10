#!/usr/bin/env ruby
# frozen_string_literal: true

# Entity Management Example for FactDb
#
# This example demonstrates:
# - Creating entities with various types
# - Managing aliases
# - Entity resolution (fuzzy matching)
# - Merging duplicate entities
# - Searching entities
# - Building entity timelines

require "bundler/setup"
require "fact_db"

log_path = File.join(__dir__, "#{File.basename(__FILE__, '.rb')}.log")

FactDb.configure do |config|
  config.database.url = ENV.fetch("DATABASE_URL", "postgres://#{ENV['USER']}@localhost/fact_db_demo")
  config.fuzzy_match_threshold = 0.85
  config.auto_merge_threshold = 0.95
  config.logger = Logger.new(log_path)
end

# Ensure database tables exist
FactDb::Database.migrate!

facts = FactDb.new
entity_service = facts.entity_service
fact_service = facts.fact_service

puts "=" * 60
puts "FactDb Entity Management Demo"
puts "=" * 60

# Section 1: Creating Entities
puts "\n--- Section 1: Creating Entities ---\n"

# Create a person entity with aliases
person = entity_service.create(
  "Robert Johnson",
  type: :person,
  aliases: ["Bob Johnson", "R. Johnson", "Bobby"],
  attributes: { email: "rjohnson@example.com", department: "Sales" },
  description: "Senior Sales Representative"
)
puts "Created person: #{person.canonical_name}"
puts "  Aliases: #{person.aliases.map(&:alias_text).join(', ')}"
puts "  Type: #{person.entity_type}"

# Create organization entities
org1 = entity_service.create(
  "Global Industries Inc",
  type: :organization,
  aliases: ["Global Industries", "GII"],
  description: "Fortune 500 manufacturing company"
)
puts "\nCreated organization: #{org1.canonical_name}"

# Create a location entity
location = entity_service.create(
  "San Francisco",
  type: :place,
  aliases: ["SF", "San Fran"],
  attributes: { country: "USA", state: "California" }
)
puts "Created place: #{location.canonical_name}"

# Section 2: Entity Resolution
puts "\n--- Section 2: Entity Resolution ---\n"

# Try to resolve entities using fuzzy matching
test_names = ["Bob Johnson", "R Johnson", "Robert J", "Global Ind", "GII"]

test_names.each do |name|
  resolved = entity_service.resolve(name, type: nil)
  if resolved
    puts "Resolved '#{name}' -> #{resolved.canonical_name} (#{resolved.entity_type})"
  else
    puts "Could not resolve '#{name}'"
  end
end

# Resolve or create - creates if not found
puts "\nUsing resolve_or_create:"
new_person = entity_service.resolve_or_create(
  "Maria Garcia",
  type: :person,
  description: "New employee"
)
puts "Result: #{new_person.canonical_name} (new: #{new_person.created_at == new_person.updated_at})"

# Section 3: Managing Aliases
puts "\n--- Section 3: Managing Aliases ---\n"

# Add more aliases to an existing entity
entity_service.add_alias(person.id, "Robert J.", alias_type: :name, confidence: 0.9)
entity_service.add_alias(person.id, "rjohnson@example.com", alias_type: :email, confidence: 1.0)

person.reload
puts "Updated aliases for #{person.canonical_name}:"
person.aliases.each do |a|
  puts "  - #{a.alias_text} (#{a.alias_type}, confidence: #{a.confidence})"
end

# Section 4: Merging Duplicate Entities
puts "\n--- Section 4: Merging Entities ---\n"

# Create a duplicate entity (simulating data entry error)
duplicate = entity_service.create(
  "Bob Johnson",
  type: :person,
  description: "Possible duplicate of Robert Johnson"
)
puts "Created potential duplicate: #{duplicate.canonical_name} (ID: #{duplicate.id})"

# Find potential duplicates
puts "\nSearching for duplicates:"
duplicates = entity_service.find_duplicates(threshold: 0.8)
duplicates.each do |dup_pair|
  puts "  Potential duplicate: #{dup_pair[:entity1].canonical_name} <-> #{dup_pair[:entity2].canonical_name}"
  puts "    Similarity: #{dup_pair[:similarity]}"
end

# Merge the duplicate into the canonical entity
puts "\nMerging entities..."
entity_service.merge(person.id, duplicate.id)
puts "Merged '#{duplicate.canonical_name}' into '#{person.canonical_name}'"

# Verify the duplicate is marked as merged
duplicate.reload
puts "Duplicate status: #{duplicate.resolution_status}"
puts "Merged into: #{duplicate.merged_into_id}"

# Section 5: Searching Entities
puts "\n--- Section 5: Searching Entities ---\n"

# Create more entities for search demo
entity_service.create("Jennifer Wilson", type: :person, description: "Marketing Manager")
entity_service.create("John Williams", type: :person, description: "Software Engineer")
entity_service.create("Wilson & Associates", type: :organization, description: "Law firm")

# Text search
puts "Search results for 'Wilson':"
results = entity_service.search("Wilson")
results.each do |entity|
  puts "  - #{entity.canonical_name} (#{entity.entity_type})"
end

# Filter by type
puts "\nPeople only:"
entity_service.by_type("person").each do |entity|
  puts "  - #{entity.canonical_name}"
end

puts "\nOrganizations only:"
entity_service.by_type("organization").each do |entity|
  puts "  - #{entity.canonical_name}"
end

# Section 6: Entity Timeline
puts "\n--- Section 6: Entity Timeline ---\n"

# Create some facts about Bob to build a timeline
fact_service.create(
  "Robert Johnson joined Global Industries as Sales Associate",
  valid_at: Date.new(2018, 3, 1),
  invalid_at: Date.new(2020, 6, 30),
  mentions: [
    { entity_id: person.id, role: :subject, text: "Robert Johnson" },
    { entity_id: org1.id, role: :object, text: "Global Industries" }
  ]
)

fact_service.create(
  "Robert Johnson promoted to Senior Sales Representative at Global Industries",
  valid_at: Date.new(2020, 7, 1),
  mentions: [
    { entity_id: person.id, role: :subject, text: "Robert Johnson" },
    { entity_id: org1.id, role: :object, text: "Global Industries" }
  ]
)

fact_service.create(
  "Robert Johnson relocated to San Francisco office",
  valid_at: Date.new(2022, 1, 15),
  mentions: [
    { entity_id: person.id, role: :subject, text: "Robert Johnson" },
    { entity_id: location.id, role: :location, text: "San Francisco" }
  ]
)

# Build timeline for the person
puts "Timeline for #{person.canonical_name}:"
timeline = entity_service.timeline_for(person.id, from: Date.new(2017, 1, 1), to: Date.today)
timeline.each do |entry|
  date_range = entry[:invalid_at] ? "#{entry[:valid_at]} - #{entry[:invalid_at]}" : "#{entry[:valid_at]} - present"
  puts "  [#{date_range}]"
  puts "    #{entry[:fact_text]}"
end

# Section 7: Statistics
puts "\n--- Section 7: Entity Statistics ---\n"

stats = entity_service.stats
puts "Total entities: #{stats[:total]}"
puts "By type:"
stats[:by_type].each do |type, count|
  puts "  #{type}: #{count}"
end
puts "By resolution status:"
stats[:by_status].each do |status, count|
  puts "  #{status}: #{count}"
end

puts "\n" + "=" * 60
puts "Entity Management Demo Complete!"
puts "=" * 60
