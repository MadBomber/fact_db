#!/usr/bin/env ruby
# frozen_string_literal: true

# Rule-Based Extraction Example for FactDb
#
# This example demonstrates:
# - Using the rule-based extractor
# - Automatic pattern detection for employment, relationships, and locations
# - Processing extracted facts into the database
# - Handling extraction results

require "bundler/setup"
require "fact_db"

FactDb.configure do |config|
  config.database_url = ENV.fetch("DATABASE_URL", "postgres://#{ENV['USER']}@localhost/fact_db_demo")
  config.default_extractor = :rule_based
end

# Ensure database tables exist
FactDb::Database.migrate!

clock = FactDb.new

puts "=" * 60
puts "FactDb Rule-Based Extraction Demo"
puts "=" * 60

# Sample documents to process
documents = [
  {
    title: "Company Announcement",
    type: :document,
    text: <<~TEXT
      FOR IMMEDIATE RELEASE - January 15, 2026

      Global Tech Solutions Appoints New Leadership Team

      Global Tech Solutions announced today that Jennifer Martinez has joined
      the company as Chief Technology Officer. Martinez, who previously served
      as VP of Engineering at DataFlow Inc from 2020 to 2025, will lead the
      company's technical strategy.

      Additionally, Michael Chen has been promoted to Chief Operating Officer,
      effective February 1, 2026. Chen has been with Global Tech Solutions
      since 2018.

      The company, headquartered in Seattle, Washington, continues to expand
      its presence in the cloud computing market.
    TEXT
  },
  {
    title: "HR Update Email",
    type: :email,
    text: <<~TEXT
      From: hr@example.com
      Subject: Team Updates - Q1 2026
      Date: January 20, 2026

      Hi team,

      Please welcome our new hires:
      - Sarah Williams joined our Marketing team on January 10, 2026
      - David Lee started as Senior Developer on January 15, 2026
      - Emma Thompson works at our London office as Regional Manager

      Also note that James Wilson left the company on December 31, 2025
      to pursue other opportunities.

      Recent relocations:
      - Lisa Anderson moved to the Austin office
      - Robert Kim now lives in San Francisco

      Best regards,
      Human Resources
    TEXT
  },
  {
    title: "Meeting Notes",
    type: :meeting_notes,
    text: <<~TEXT
      Project Status Meeting - January 22, 2026

      Attendees: Tom Baker (Project Manager), Anna Kowalski (Lead Developer)

      Updates:
      - Tom Baker is leading the Alpha project launch scheduled for Q2
      - Anna Kowalski is responsible for the backend infrastructure
      - Partnership discussion: Maria Santos is CEO of TechPartner Corp
      - TechPartner Corp is headquartered in Miami, Florida

      Action Items:
      - Tom to schedule follow-up with Maria Santos
      - Anna reports to Tom Baker for the Alpha project
    TEXT
  }
]

# Create the rule-based extractor
extractor = FactDb::Extractors::Base.for(:rule_based)

# Section 1: Process Each Document
puts "\n--- Section 1: Processing Documents ---\n"

documents.each_with_index do |doc, index|
  puts "\n#{'=' * 40}"
  puts "Document #{index + 1}: #{doc[:title]}"
  puts "=" * 40

  # Ingest the content
  content = clock.ingest(
    doc[:text],
    type: doc[:type],
    title: doc[:title],
    captured_at: Time.now
  )
  puts "Ingested content ID: #{content.id}"

  # Extract facts and entities
  context = { source_id: content.id, captured_at: content.captured_at }
  extracted_facts = extractor.extract(doc[:text], context)

  puts "\nExtracted #{extracted_facts.length} facts:"
  extracted_facts.each_with_index do |fact, i|
    puts "  #{i + 1}. #{fact[:text]}"
    puts "     Confidence: #{fact[:confidence]}"
    puts "     Valid from: #{fact[:valid_at]}" if fact[:valid_at]
    puts "     Valid until: #{fact[:invalid_at]}" if fact[:invalid_at]
    if fact[:mentions]&.any?
      puts "     Mentions: #{fact[:mentions].map { |m| "#{m[:name]} (#{m[:role]})" }.join(', ')}"
    end
  end

  # Also extract entities
  entities = extractor.extract_entities(doc[:text])
  if entities.any?
    puts "\nExtracted #{entities.length} entities:"
    entities.each do |entity|
      puts "  - #{entity[:name]} (#{entity[:type]})"
    end
  end
end

# Section 2: Save Extracted Facts to Database
puts "\n\n--- Section 2: Saving Extracted Facts ---\n"

entity_service = clock.entity_service
fact_service = clock.fact_service

# Process first document in detail
sample_doc = documents.first
content = clock.content_service.search(sample_doc[:title]).first
context = { source_id: content.id, captured_at: content.captured_at }
result = extractor.extract(sample_doc[:text], context)

result.each do |fact_data|
  # Resolve or create mentioned entities
  mention_records = []

  fact_data[:mentions]&.each do |mention|
    # Try to resolve the entity, create if not found
    entity = entity_service.resolve_or_create(
      mention[:name],
      type: mention[:type] || :unknown,
      description: "Auto-extracted entity"
    )

    mention_records << {
      entity_id: entity.id,
      role: mention[:role],
      text: mention[:name],
      confidence: mention[:confidence] || fact_data[:confidence]
    }
  end

  # Create the fact
  fact = fact_service.create(
    fact_data[:text],
    valid_at: fact_data[:valid_at] || Date.today,
    invalid_at: fact_data[:invalid_at],
    extraction_method: :rule_based,
    confidence: fact_data[:confidence],
    mentions: mention_records
  )

  # Link to source content
  fact.add_source(content: content, type: :primary, confidence: fact_data[:confidence])

  puts "Saved fact: #{fact.fact_text}"
  puts "  ID: #{fact.id}, Mentions: #{fact.entity_mentions.count}"
end

# Section 3: Query the Extracted Data
puts "\n--- Section 3: Querying Extracted Data ---\n"

# Find all extracted entities
puts "\nAll extracted entities:"
FactDb::Models::Entity.where(resolution_status: :resolved).order(:canonical_name).each do |entity|
  fact_count = entity.facts.count
  puts "  #{entity.canonical_name} (#{entity.entity_type}) - #{fact_count} facts"
end

# Find facts by extraction method
puts "\nFacts extracted by rule-based extractor:"
FactDb::Models::Fact.by_extraction_method(:rule_based).limit(10).each do |fact|
  puts "  [#{fact.confidence}] #{fact.fact_text}"
end

# Section 4: Pattern Examples
puts "\n--- Section 4: Extraction Pattern Examples ---\n"

test_patterns = [
  "John Smith works at Acme Corp as a Senior Engineer.",
  "Mary Johnson joined Microsoft on March 15, 2024.",
  "The CEO of Apple is Tim Cook.",
  "Sarah left Google on December 1, 2025.",
  "Amazon is headquartered in Seattle.",
  "Bob lives in New York City.",
  "Dr. Lisa Chen married James Wong in 2023.",
]

puts "Testing individual patterns:\n"
test_patterns.each do |pattern|
  result = extractor.extract(pattern, {})
  if result.any?
    puts "Input: \"#{pattern}\""
    result.each do |fact|
      puts "  -> #{fact[:text]} (confidence: #{fact[:confidence]})"
    end
    puts
  else
    puts "Input: \"#{pattern}\""
    puts "  -> No facts extracted"
    puts
  end
end

# Section 5: Statistics
puts "\n--- Section 5: Extraction Statistics ---\n"

content_stats = clock.content_service.stats
fact_stats = clock.fact_service.stats
entity_stats = entity_service.stats

puts "Content ingested: #{content_stats[:total]}"
puts "Entities created: #{entity_stats[:total]}"
puts "Facts extracted: #{fact_stats[:total]}"

if fact_stats[:by_extraction_method]
  puts "\nFacts by extraction method:"
  fact_stats[:by_extraction_method].each do |method, count|
    puts "  #{method}: #{count}"
  end
end

puts "\n" + "=" * 60
puts "Rule-Based Extraction Demo Complete!"
puts "=" * 60
