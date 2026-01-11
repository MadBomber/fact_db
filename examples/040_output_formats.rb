#!/usr/bin/env ruby
# frozen_string_literal: true

# Output Formats Example for FactDb
#
# This example demonstrates:
# - Different output formats for LLM consumption
# - JSON, Triples, Cypher, and Text transformers
# - How each format represents the same data differently

require_relative "utilities"

demo_setup!("FactDb Output Formats Demo")
demo_configure_logging(__FILE__)

facts = FactDb.new
entity_service = facts.entity_service
fact_service = facts.fact_service

demo_section("Setup: Creating Sample Data")

# Create entities
paula = entity_service.resolve_or_create(
  "Paula Chen",
  type: :person,
  aliases: ["P. Chen"],
  description: "Principal Engineer"
)

microsoft = entity_service.resolve_or_create(
  "Microsoft",
  type: :organization,
  aliases: ["MSFT"],
  description: "Technology company"
)

seattle = entity_service.resolve_or_create(
  "Seattle",
  type: :place,
  description: "City in Washington state"
)

puts "Created entities: #{paula.canonical_name}, #{microsoft.canonical_name}, #{seattle.canonical_name}"

# Create facts
fact_service.create(
  "Paula Chen is Principal Engineer at Microsoft",
  valid_at: Date.new(2024, 1, 10),
  extraction_method: :manual,
  confidence: 1.0,
  mentions: [
    { entity_id: paula.id, role: :subject, text: "Paula Chen" },
    { entity_id: microsoft.id, role: :object, text: "Microsoft" }
  ]
)

fact_service.create(
  "Paula Chen works at the Seattle office",
  valid_at: Date.new(2024, 1, 10),
  extraction_method: :manual,
  confidence: 0.95,
  mentions: [
    { entity_id: paula.id, role: :subject, text: "Paula Chen" },
    { entity_id: seattle.id, role: :location, text: "Seattle" }
  ]
)

fact_service.create(
  "Paula Chen reports to Sarah Kim",
  valid_at: Date.new(2024, 1, 10),
  extraction_method: :manual,
  confidence: 0.9,
  mentions: [
    { entity_id: paula.id, role: :subject, text: "Paula Chen" }
  ]
)

puts "Created facts about Paula Chen"

demo_section("Section 1: JSON Format (Default)")

json_results = facts.query_facts(entity: paula.id, format: :json)
puts "\nJSON output:"
puts JSON.pretty_generate(json_results.to_h)

demo_section("Section 2: Triples Format (Subject-Predicate-Object)")

triples_results = facts.query_facts(entity: paula.id, format: :triples)
puts "\nTriples output:"
triples_results.each do |triple|
  puts "  #{triple.inspect}"
end

puts <<~EXPLANATION

  Triples format is ideal for:
  - Knowledge graph representations
  - Semantic reasoning
  - LLM structured understanding
EXPLANATION

demo_section("Section 3: Cypher Format (Graph Notation)")

cypher_results = facts.query_facts(entity: paula.id, format: :cypher)
puts "\nCypher output:"
puts cypher_results

puts <<~EXPLANATION

  Cypher format is ideal for:
  - Graph database imports (Neo4j compatible)
  - Visualizing entity relationships
  - Understanding connection patterns
EXPLANATION

demo_section("Section 4: Text Format (Human-Readable)")

text_results = facts.query_facts(entity: paula.id, format: :text)
puts "\nText output:"
puts text_results

puts <<~EXPLANATION

  Text format is ideal for:
  - Direct LLM consumption
  - Human debugging
  - Report generation
EXPLANATION

demo_section("Section 5: Raw Format (ActiveRecord Objects)")

raw_results = facts.query_facts(entity: paula.id, format: :raw)
puts "\nRaw output (first result):"
if raw_results.respond_to?(:raw_facts) && raw_results.raw_facts.any?
  fact = raw_results.raw_facts.first
  puts "  Class: #{fact.class}"
  puts "  ID: #{fact.id}"
  puts "  Text: #{fact.fact_text}"
  puts "  Valid at: #{fact.valid_at}"
else
  puts "  Results: #{raw_results.inspect}"
end

demo_section("Section 6: Format Comparison - Same Query, Different Views")

puts "\nQuerying current facts for Paula Chen in all formats:\n"

formats = %i[json triples cypher text]

formats.each do |format|
  puts "\n--- #{format.upcase} ---"
  result = facts.current_facts_for(paula.id, format: format)

  case format
  when :json
    if result.respond_to?(:to_h)
      puts "#{result.fact_count} facts, #{result.entity_count} entities"
    else
      puts "#{result.size} facts" if result.respond_to?(:size)
    end
  when :triples
    puts "#{result.size} triples generated"
  when :cypher
    puts "#{result.lines.count} lines of Cypher notation"
  when :text
    puts result.lines.first(5).join
    puts "..." if result.lines.count > 5
  end
end

demo_section("Section 7: Temporal Queries with Formats")

puts "\nFacts at specific date (2024-06-01) in Cypher format:"
temporal_cypher = facts.facts_at(Date.new(2024, 6, 1), entity: paula.id, format: :cypher)
puts temporal_cypher

demo_footer
