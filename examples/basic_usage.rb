#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic Usage Example for FactDb
#
# This example demonstrates:
# - Configuring FactDb
# - Ingesting content
# - Creating entities
# - Creating facts manually
# - Querying facts

require "bundler/setup"
require "fact_db"

# Configure FactDb
FactDb.configure do |config|
  config.database_url = ENV.fetch("DATABASE_URL", "postgres://localhost/fact_db_demo")
  config.default_extractor = :manual
  config.fuzzy_match_threshold = 0.85
end

# Create a new FactDb instance (the "clock")
clock = FactDb.new

puts "=" * 60
puts "FactDb Basic Usage Demo"
puts "=" * 60

# Step 1: Ingest some content
puts "\n--- Step 1: Ingesting Content ---\n"

email_content = <<~EMAIL
  From: hr@acme.com
  To: all@acme.com
  Subject: New Hire Announcement
  Date: January 8, 2026

  We are pleased to announce that Jane Smith has joined Acme Corp
  as our new Director of Engineering. Jane comes to us from
  TechStartup Inc where she served as VP of Engineering for 3 years.

  Please join me in welcoming Jane to the team!

  Best regards,
  HR Department
EMAIL

content = clock.ingest(
  email_content,
  type: :email,
  title: "New Hire Announcement - Jane Smith",
  captured_at: Time.new(2026, 1, 8)
)

puts "Ingested content ID: #{content.id}"
puts "Content hash: #{content.content_hash}"
puts "Word count: #{content.word_count}"

# Step 2: Create entities
puts "\n--- Step 2: Creating Entities ---\n"

entity_service = clock.entity_service

jane = entity_service.create(
  "Jane Smith",
  type: :person,
  aliases: ["J. Smith"],
  description: "Director of Engineering at Acme Corp"
)
puts "Created entity: #{jane.canonical_name} (ID: #{jane.id})"

acme = entity_service.create(
  "Acme Corp",
  type: :organization,
  aliases: ["Acme", "Acme Corporation"],
  description: "Technology company"
)
puts "Created entity: #{acme.canonical_name} (ID: #{acme.id})"

techstartup = entity_service.create(
  "TechStartup Inc",
  type: :organization,
  aliases: ["TechStartup"],
  description: "Technology startup company"
)
puts "Created entity: #{techstartup.canonical_name} (ID: #{techstartup.id})"

# Step 3: Create facts
puts "\n--- Step 3: Creating Facts ---\n"

fact_service = clock.fact_service

# Fact 1: Jane works at Acme
fact1 = fact_service.create(
  "Jane Smith is Director of Engineering at Acme Corp",
  valid_at: Date.new(2026, 1, 8),
  extraction_method: :manual,
  confidence: 1.0,
  mentions: [
    { entity_id: jane.id, role: :subject, text: "Jane Smith" },
    { entity_id: acme.id, role: :object, text: "Acme Corp" }
  ]
)
puts "Created fact: #{fact1.fact_text}"
puts "  Valid from: #{fact1.valid_at}"

# Fact 2: Jane previously worked at TechStartup (now invalid)
fact2 = fact_service.create(
  "Jane Smith was VP of Engineering at TechStartup Inc",
  valid_at: Date.new(2023, 1, 1),
  invalid_at: Date.new(2026, 1, 7),
  extraction_method: :manual,
  confidence: 0.9,
  mentions: [
    { entity_id: jane.id, role: :subject, text: "Jane Smith" },
    { entity_id: techstartup.id, role: :object, text: "TechStartup Inc" }
  ]
)
puts "Created fact: #{fact2.fact_text}"
puts "  Valid from: #{fact2.valid_at} to #{fact2.invalid_at}"

# Link facts to source content
fact1.add_source(content: content, type: :primary, confidence: 1.0)
fact2.add_source(content: content, type: :supporting, confidence: 0.8)

# Step 4: Query facts
puts "\n--- Step 4: Querying Facts ---\n"

# Get current facts about Jane
puts "\nCurrent facts about Jane Smith:"
current_facts = fact_service.current_facts(entity: jane.id)
current_facts.each do |fact|
  puts "  - #{fact.fact_text}"
end

# Get facts valid at a specific date (when Jane was at TechStartup)
puts "\nFacts about Jane on January 1, 2024:"
past_facts = fact_service.facts_at(Date.new(2024, 1, 1), entity: jane.id)
past_facts.each do |fact|
  puts "  - #{fact.fact_text}"
end

# Get all facts (including historical)
puts "\nAll facts in the system:"
all_facts = clock.query_facts
all_facts.each do |fact|
  status = fact.invalid_at ? "(historical)" : "(current)"
  puts "  - #{fact.fact_text} #{status}"
end

# Step 5: Get statistics
puts "\n--- Step 5: Statistics ---\n"

puts "Content stats: #{clock.content_service.stats}"
puts "Entity stats: #{entity_service.stats}"
puts "Fact stats: #{fact_service.stats}"

puts "\n" + "=" * 60
puts "Demo complete!"
puts "=" * 60
