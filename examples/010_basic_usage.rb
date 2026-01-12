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

require_relative "utilities"
require "amazing_print"

demo_setup!("FactDb Basic Usage Demo")
demo_configure_logging(__FILE__)

FactDb.configure do |config|
  config.default_extractor = :manual
end

# Create a new FactDb instance
facts = FactDb.new

demo_section("Step 1: Ingesting Content")

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

content = facts.ingest(
  email_content,
  type: :email,
  title: "New Hire Announcement - Jane Smith",
  captured_at: Time.new(2026, 1, 8)
)

puts "Ingested content ID: #{content.id}"
puts "Content hash: #{content.content_hash}"
puts "Word count: #{content.word_count}"

demo_section("Step 2: Creating/Finding Entities")

entity_service = facts.entity_service

jane = entity_service.resolve_or_create(
  "Jane Smith",
  type: :person,
  aliases: ["J. Smith"],
  description: "Director of Engineering at Acme Corp"
)
puts "Entity: #{jane.name} (ID: #{jane.id})"

acme = entity_service.resolve_or_create(
  "Acme Corp",
  type: :organization,
  aliases: ["Acme", "Acme Corporation"],
  description: "Technology company"
)
puts "Entity: #{acme.name} (ID: #{acme.id})"

techstartup = entity_service.resolve_or_create(
  "TechStartup Inc",
  type: :organization,
  aliases: ["TechStartup"],
  description: "Technology startup company"
)
puts "Entity: #{techstartup.name} (ID: #{techstartup.id})"

demo_section("Step 3: Creating/Finding Facts")

fact_service = facts.fact_service

# Fact 1: Jane works at Acme
fact1 = fact_service.find_or_create(
  "Jane Smith is Director of Engineering at Acme Corp",
  valid_at: Date.new(2026, 1, 8),
  extraction_method: :manual,
  confidence: 1.0,
  mentions: [
    { entity_id: jane.id, role: :subject, text: "Jane Smith" },
    { entity_id: acme.id, role: :object, text: "Acme Corp" }
  ]
)
puts "Fact: #{fact1.text}"
puts "  Valid from: #{fact1.valid_at}"

# Fact 2: Jane previously worked at TechStartup (now invalid)
fact2 = fact_service.find_or_create(
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
puts "Fact: #{fact2.text}"
puts "  Valid from: #{fact2.valid_at} to #{fact2.invalid_at}"

# Link facts to source content (skip if already linked)
fact1.add_source(content: content, type: :primary, confidence: 1.0) rescue nil
fact2.add_source(content: content, type: :supporting, confidence: 0.8) rescue nil

demo_section("Step 4: Querying Facts")

# Get current facts about Jane
puts "\nCurrent facts about Jane Smith:"
current_facts = fact_service.current_facts(entity: jane.id)
current_facts.each do |fact|
  puts "  - #{fact.text}"
end

# Get facts valid at a specific date (when Jane was at TechStartup)
puts "\nFacts about Jane on January 1, 2024:"
past_facts = fact_service.facts_at(Date.new(2024, 1, 1), entity: jane.id)
past_facts.each do |fact|
  puts "  - #{fact.text}"
end

# Get all facts (including historical)
puts "\nAll facts in the system:"
all_facts = facts.query_facts
all_facts.each_fact do |fact|
  status = fact[:invalid_at] ? "(historical)" : "(current)"
  puts "  - #{fact[:text]} #{status}"
end

demo_section("Step 5: Statistics")

puts "\nContent stats:"
ap facts.content_service.stats

puts "\nEntity stats:"
ap entity_service.stats

puts "\nFact stats:"
ap fact_service.stats

demo_footer
