#!/usr/bin/env ruby
# frozen_string_literal: true

# Introspection Example for FactDb
#
# This example demonstrates:
# - Schema introspection - discovering what the system knows
# - Topic introspection - examining specific entities
# - Query suggestions based on available data
# - Retrieval strategy recommendations
# - New service methods for entity analysis

require "bundler/setup"
require "fact_db"

log_path = File.join(__dir__, "#{File.basename(__FILE__, '.rb')}.log")

FactDb.configure do |config|
  config.database.url = ENV.fetch("DATABASE_URL", "postgres://#{ENV['USER']}@localhost/fact_db_demo")
  config.logger = Logger.new(log_path)
end

FactDb::Database.migrate!

facts = FactDb.new
entity_service = facts.entity_service
fact_service = facts.fact_service

puts "=" * 60
puts "FactDb Introspection Demo"
puts "=" * 60

# Setup: Create sample data
puts "\n--- Setup: Creating Sample Data ---\n"

# Create entities
maria = entity_service.resolve_or_create(
  "Maria Santos",
  type: :person,
  aliases: ["M. Santos"],
  description: "Engineering Manager"
)

raj = entity_service.resolve_or_create(
  "Raj Patel",
  type: :person,
  description: "Senior Engineer"
)

sarah = entity_service.resolve_or_create(
  "Sarah Kim",
  type: :person,
  description: "Software Engineer"
)

techcorp = entity_service.resolve_or_create(
  "TechCorp",
  type: :organization,
  description: "Software company"
)

austin = entity_service.resolve_or_create(
  "Austin",
  type: :place,
  description: "City in Texas"
)

puts "Created 5 entities"

# Create facts with various relationships
fact_service.create(
  "Maria Santos is Engineering Manager at TechCorp",
  valid_at: Date.new(2023, 1, 1),
  extraction_method: :manual,
  confidence: 1.0,
  mentions: [
    { entity_id: maria.id, role: :subject, text: "Maria Santos" },
    { entity_id: techcorp.id, role: :object, text: "TechCorp" }
  ]
)

fact_service.create(
  "Raj Patel reports to Maria Santos",
  valid_at: Date.new(2023, 6, 1),
  extraction_method: :manual,
  mentions: [
    { entity_id: raj.id, role: :subject, text: "Raj Patel" },
    { entity_id: maria.id, role: :object, text: "Maria Santos" }
  ]
)

fact_service.create(
  "Sarah Kim reports to Maria Santos",
  valid_at: Date.new(2024, 1, 1),
  extraction_method: :manual,
  mentions: [
    { entity_id: sarah.id, role: :subject, text: "Sarah Kim" },
    { entity_id: maria.id, role: :object, text: "Maria Santos" }
  ]
)

# Historical fact (superseded)
old_role = fact_service.create(
  "Maria Santos was Senior Engineer at TechCorp",
  valid_at: Date.new(2020, 1, 1),
  invalid_at: Date.new(2022, 12, 31),
  extraction_method: :manual,
  status: :superseded,
  mentions: [
    { entity_id: maria.id, role: :subject, text: "Maria Santos" },
    { entity_id: techcorp.id, role: :object, text: "TechCorp" }
  ]
)

fact_service.create(
  "Maria Santos works at Austin office",
  valid_at: Date.new(2023, 1, 1),
  extraction_method: :rule_based,
  mentions: [
    { entity_id: maria.id, role: :subject, text: "Maria Santos" },
    { entity_id: austin.id, role: :location, text: "Austin" }
  ]
)

puts "Created facts with various relationships and history"

# Section 1: Schema Introspection
puts "\n" + "=" * 60
puts "Section 1: Schema Introspection - facts.introspect()"
puts "=" * 60

schema = facts.introspect
puts "\nSystem Capabilities:"
schema[:capabilities].each { |c| puts "  - #{c}" }

puts "\nEntity Types in Database:"
schema[:entity_types].each { |t| puts "  - #{t}" }

puts "\nAvailable Fact Statuses:"
schema[:fact_statuses].each { |s| puts "  - #{s}" }

puts "\nExtraction Methods:"
schema[:extraction_methods].each { |m| puts "  - #{m}" }

puts "\nSupported Output Formats:"
schema[:output_formats].each { |f| puts "  - #{f}" }

puts "\nRetrieval Strategies:"
schema[:retrieval_strategies].each { |s| puts "  - #{s}" }

puts "\nStatistics:"
puts JSON.pretty_generate(schema[:statistics])

# Section 2: Topic Introspection
puts "\n" + "=" * 60
puts "Section 2: Topic Introspection - facts.introspect('Maria Santos')"
puts "=" * 60

maria_info = facts.introspect("Maria Santos")
if maria_info
  puts "\nEntity Information:"
  puts "  Name: #{maria_info[:entity][:canonical_name]}"
  puts "  Type: #{maria_info[:entity][:entity_type]}"
  puts "  Status: #{maria_info[:entity][:resolution_status]}"

  puts "\nFact Coverage:"
  puts "  Canonical: #{maria_info[:coverage][:facts][:canonical]}"
  puts "  Superseded: #{maria_info[:coverage][:facts][:superseded]}"
  puts "  Corroborated: #{maria_info[:coverage][:facts][:corroborated]}"
  puts "  Synthesized: #{maria_info[:coverage][:facts][:synthesized]}"

  puts "\nTimespan:"
  puts "  From: #{maria_info[:coverage][:timespan][:from]}"
  puts "  To: #{maria_info[:coverage][:timespan][:to]}"

  puts "\nRelationship Types:"
  maria_info[:relationships].each { |r| puts "  - #{r}" }

  puts "\nSuggested Queries:"
  maria_info[:suggested_queries].each { |q| puts "  - #{q}" }
else
  puts "Entity not found"
end

# Section 3: Query Suggestions
puts "\n" + "=" * 60
puts "Section 3: Query Suggestions - facts.suggest_queries()"
puts "=" * 60

%w[Maria\ Santos Raj\ Patel TechCorp].each do |topic|
  suggestions = facts.suggest_queries(topic)
  puts "\nSuggested queries for '#{topic}':"
  if suggestions.empty?
    puts "  (no suggestions available)"
  else
    suggestions.each { |s| puts "  - #{s}" }
  end
end

# Section 4: Strategy Suggestions
puts "\n" + "=" * 60
puts "Section 4: Retrieval Strategy Suggestions"
puts "=" * 60

test_queries = [
  "What happened last week?",
  "Who works at TechCorp?",
  "Find similar projects",
  "Current team members",
  "Changes since January"
]

test_queries.each do |query|
  strategies = facts.suggest_strategies(query)
  puts "\nQuery: \"#{query}\""
  puts "  Recommended strategies:"
  strategies.each do |s|
    puts "    - #{s[:strategy]}: #{s[:description]}"
  end
end

# Section 5: New Entity Service Methods
puts "\n" + "=" * 60
puts "Section 5: New Entity Service Methods"
puts "=" * 60

puts "\n--- relationship_types ---"
puts "All relationship types in database:"
all_relationships = entity_service.relationship_types
all_relationships.each { |r| puts "  - #{r}" }

puts "\n--- relationship_types_for(entity_id) ---"
puts "Relationship types for Maria Santos:"
maria_relationships = entity_service.relationship_types_for(maria.id)
maria_relationships.each { |r| puts "  - #{r}" }

puts "\n--- timespan_for(entity_id) ---"
puts "Timespan of facts for Maria Santos:"
timespan = entity_service.timespan_for(maria.id)
puts "  From: #{timespan[:from]}"
puts "  To: #{timespan[:to]}"

# Section 6: New Fact Service Methods
puts "\n" + "=" * 60
puts "Section 6: New Fact Service Methods"
puts "=" * 60

puts "\n--- fact_stats(entity_id) ---"
puts "Fact statistics for Maria Santos:"
maria_stats = fact_service.fact_stats(maria.id)
maria_stats.each { |status, count| puts "  #{status}: #{count}" }

puts "\nFact statistics for all facts:"
all_stats = fact_service.fact_stats
all_stats.each { |status, count| puts "  #{status}: #{count}" }

# Section 7: Practical Use Case - LLM Context Building
puts "\n" + "=" * 60
puts "Section 7: Practical Use Case - Building LLM Context"
puts "=" * 60

puts "\nBuilding context for an LLM query about Maria Santos:\n"

# Step 1: Introspect the topic
topic_info = facts.introspect("Maria Santos")

puts "1. Entity identified: #{topic_info[:entity][:canonical_name]} (#{topic_info[:entity][:entity_type]})"
puts "   Coverage: #{topic_info[:coverage][:facts][:canonical]} current facts, #{topic_info[:coverage][:facts][:superseded]} historical"

# Step 2: Get facts in LLM-friendly format
puts "\n2. Facts in text format for LLM consumption:"
facts_text = facts.current_facts_for(maria.id, format: :text)
puts facts_text

# Step 3: Get facts in structured format for reasoning
puts "\n3. Facts as triples for structured reasoning:"
facts_triples = facts.current_facts_for(maria.id, format: :triples)
facts_triples.take(5).each { |t| puts "   #{t.inspect}" }
puts "   ..." if facts_triples.size > 5

# Step 4: Suggest follow-up queries
puts "\n4. Suggested follow-up queries:"
topic_info[:suggested_queries].each { |q| puts "   - #{q}" }

puts "\n" + "=" * 60
puts "Introspection Demo Complete!"
puts "=" * 60
