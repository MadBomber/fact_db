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

require_relative "utilities"

demo_setup!("FactDb Entity Management Demo")
demo_configure_logging(__FILE__)

facts = FactDb.new
entity_service = facts.entity_service
fact_service = facts.fact_service

demo_section("Section 1: Creating Entities")

# Create a person entity with aliases
person = entity_service.create(
  "Robert Johnson",
  kind: :person,
  aliases: ["Bob Johnson", "R. Johnson", "Bobby"],
  attributes: { email: "rjohnson@example.com", department: "Sales" },
  description: "Senior Sales Representative"
)
puts "Created person: #{person.name}"
puts "  Aliases: #{person.aliases.map(&:name).join(', ')}"
puts "  Type: #{person.kind}"

# Create organization entities
org1 = entity_service.create(
  "Global Industries Inc",
  kind: :organization,
  aliases: ["Global Industries", "GII"],
  description: "Fortune 500 manufacturing company"
)
puts "\nCreated organization: #{org1.name}"

# Create a location entity
location = entity_service.create(
  "San Francisco",
  kind: :place,
  aliases: ["SF", "San Fran"],
  attributes: { country: "USA", state: "California" }
)
puts "Created place: #{location.name}"

demo_section("Section 2: Entity Resolution")

# Try to resolve entities using fuzzy matching
test_names = ["Bob Johnson", "R Johnson", "Robert J", "Global Ind", "GII"]

test_names.each do |name|
  resolved = entity_service.resolve(name, kind: nil)
  if resolved
    puts "Resolved '#{name}' -> #{resolved.name} (#{resolved.kind})"
  else
    puts "Could not resolve '#{name}'"
  end
end

# Resolve or create - creates if not found
puts "\nUsing resolve_or_create:"
new_person = entity_service.resolve_or_create(
  "Maria Garcia",
  kind: :person,
  description: "New employee"
)
puts "Result: #{new_person.name} (new: #{new_person.created_at == new_person.updated_at})"

demo_section("Section 3: Managing Aliases")

# Add more aliases to an existing entity
entity_service.add_alias(person.id, "Robert J.", kind: :name, confidence: 0.9)
entity_service.add_alias(person.id, "rjohnson@example.com", kind: :email, confidence: 1.0)

person.reload
puts "Updated aliases for #{person.name}:"
person.aliases.each do |a|
  puts "  - #{a.name} (#{a.kind}, confidence: #{a.confidence})"
end

demo_section("Section 4: Merging Entities")

# Create a duplicate entity (simulating data entry error)
# Using "Robert Johnsen" (misspelling) to demonstrate fuzzy matching
duplicate = entity_service.create(
  "Robert Johnsen",
  kind: :person,
  description: "Possible duplicate of Robert Johnson (typo)"
)
puts "Created potential duplicate: #{duplicate.name} (ID: #{duplicate.id})"

# Find potential duplicates
puts "\nSearching for duplicates:"
duplicates = entity_service.find_duplicates(threshold: 0.8)
if duplicates.empty?
  puts "  No duplicates found above threshold 0.8"
else
  duplicates.each do |dup_pair|
    puts "  Potential duplicate: #{dup_pair[:entity1].name} (ID: #{dup_pair[:entity1].id}) <-> #{dup_pair[:entity2].name} (ID: #{dup_pair[:entity2].id})"
    puts "    Similarity: #{dup_pair[:similarity].round(3)}"
  end
end

# Merge the duplicate into the canonical entity
puts "\nMerging entities..."
entity_service.merge(person.id, duplicate.id)
puts "Merged '#{duplicate.name}' into '#{person.name}'"

# Verify the duplicate is marked as merged
duplicate.reload
puts "Duplicate status: #{duplicate.resolution_status}"
puts "Canonical ID: #{duplicate.canonical_id}"

demo_section("Section 5: Searching Entities")

# Create more entities for search demo
entity_service.create("Jennifer Wilson", kind: :person, description: "Marketing Manager")
entity_service.create("John Williams", kind: :person, description: "Software Engineer")
entity_service.create("Wilson & Associates", kind: :organization, description: "Law firm")

# Text search
puts "Search results for 'Wilson':"
results = entity_service.search("Wilson")
results.each do |entity|
  puts "  - #{entity.name} (#{entity.kind})"
end

# Filter by type
puts "\nPeople only:"
entity_service.by_kind("person").each do |entity|
  puts "  - #{entity.name}"
end

puts "\nOrganizations only:"
entity_service.by_kind("organization").each do |entity|
  puts "  - #{entity.name}"
end

demo_section("Section 6: Entity Timeline")

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
puts "Timeline for #{person.name}:"
timeline = entity_service.timeline_for(person.id, from: Date.new(2017, 1, 1), to: Date.today)
timeline.each do |entry|
  date_range = entry[:invalid_at] ? "#{entry[:valid_at]} - #{entry[:invalid_at]}" : "#{entry[:valid_at]} - present"
  puts "  [#{date_range}]"
  puts "    #{entry[:text]}"
end

demo_section("Section 7: Entity Statistics")

stats = entity_service.stats
puts "Total entities: #{stats[:total]}"
puts "By kind:"
stats[:by_kind].each do |kind, count|
  puts "  #{kind}: #{count}"
end
puts "By resolution status:"
stats[:by_status].each do |status, count|
  puts "  #{status}: #{count}"
end

demo_footer("Entity Management Demo Complete!")
