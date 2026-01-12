#!/usr/bin/env ruby
# frozen_string_literal: true

# Database Dump Utility for FactDb
#
# Dumps the contents of the fact_db_demo database in a structured format
# for verification and inspection.
#
# Usage:
#   ruby dump_database.rb                # Full dump
#   ruby dump_database.rb --summary      # Summary only
#   ruby dump_database.rb --entities     # Entities only
#   ruby dump_database.rb --facts        # Facts only
#   ruby dump_database.rb --sources      # Sources only
#   ruby dump_database.rb --search TERM  # Search facts/entities

require_relative "utilities"

# Note: CLI tool - uses cli_setup! which does NOT reset database

class DatabaseDumper
  def initialize
    setup_factdb
  end

  def run(options = {})
    puts "=" * 70
    puts "FactDb Database Dump"
    puts "=" * 70
    puts "Database: #{FactDb.config.database.url}"
    puts "Timestamp: #{Time.now}"
    puts

    if options[:search]
      search(options[:search])
    elsif options[:summary]
      dump_summary
    elsif options[:entities]
      dump_entities
    elsif options[:facts]
      dump_facts
    elsif options[:sources]
      dump_sources
    else
      dump_summary
      dump_sources
      dump_entities
      dump_facts
      dump_relationships
    end
  end

  private

  def setup_factdb
    DemoUtilities.ensure_demo_environment!
    DemoUtilities.require_fact_db!

    FactDb.configure do |config|
      config.logger = Logger.new("/dev/null")
    end

    FactDb::Database.establish_connection!
  end

  def dump_summary
    puts "\n" + "=" * 70
    puts "SUMMARY"
    puts "=" * 70

    source_count = FactDb::Models::Source.count
    entity_count = FactDb::Models::Entity.count
    fact_count = FactDb::Models::Fact.count
    mention_count = FactDb::Models::EntityMention.count
    fact_source_count = FactDb::Models::FactSource.count

    puts <<~SUMMARY
      Source records:      #{source_count.to_s.rjust(6)}
      Entity records:      #{entity_count.to_s.rjust(6)}
      Fact records:        #{fact_count.to_s.rjust(6)}
      Entity mentions:     #{mention_count.to_s.rjust(6)}
      Fact sources:        #{fact_source_count.to_s.rjust(6)}
    SUMMARY

    if entity_count > 0
      puts "\nEntities by kind:"
      FactDb::Models::Entity.group(:kind).count.sort_by { |_, v| -v }.each do |kind, count|
        puts "  #{kind.to_s.ljust(20)} #{count.to_s.rjust(6)}"
      end
    end

    if fact_count > 0
      puts "\nFacts by extraction method:"
      FactDb::Models::Fact.group(:extraction_method).count.each do |method, count|
        puts "  #{method.to_s.ljust(20)} #{count.to_s.rjust(6)}"
      end

      puts "\nFacts by status:"
      FactDb::Models::Fact.group(:status).count.each do |status, count|
        puts "  #{status.to_s.ljust(20)} #{count.to_s.rjust(6)}"
      end
    end

    if source_count > 0
      puts "\nSources by kind:"
      FactDb::Models::Source.group(:kind).count.each do |kind, count|
        puts "  #{kind.to_s.ljust(20)} #{count.to_s.rjust(6)}"
      end
    end
  end

  def dump_sources
    puts "\n" + "=" * 70
    puts "SOURCES"
    puts "=" * 70

    sources = FactDb::Models::Source.order(:created_at)

    if sources.empty?
      puts "  (no source records)"
      return
    end

    sources.each do |source|
      puts "\n#{'-' * 60}"
      puts "ID: #{source.id}"
      puts "Title: #{source.title || '(untitled)'}"
      puts "Kind: #{source.kind}"
      puts "Hash: #{source.content_hash[0..16]}..."
      puts "Captured: #{source.captured_at}"
      puts "Created: #{source.created_at}"

      if source.metadata.present?
        puts "Metadata: #{source.metadata.to_json}"
      end

      # Show linked facts count
      fact_count = source.facts.count
      puts "Linked facts: #{fact_count}"

      # Preview of content
      preview = source.content.to_s.gsub(/\s+/, ' ').strip[0..200]
      puts "Preview: #{preview}..." if preview.present?
    end
  end

  def dump_entities
    puts "\n" + "=" * 70
    puts "ENTITIES"
    puts "=" * 70

    entities = FactDb::Models::Entity.order(:kind, :name)

    if entities.empty?
      puts "  (no entity records)"
      return
    end

    current_kind = nil
    entities.each do |entity|
      if entity.kind != current_kind
        current_kind = entity.kind
        puts "\n--- #{current_kind.upcase} ---"
      end

      mention_count = entity.entity_mentions.count
      fact_count = entity.facts.count

      puts "\n  #{entity.name}"
      puts "    ID: #{entity.id}"
      puts "    Aliases: #{entity.all_aliases.join(', ')}" if entity.all_aliases.any?
      puts "    Description: #{entity.description}" if entity.description.present?
      puts "    Resolution: #{entity.resolution_status}"
      puts "    Mentions: #{mention_count}, Facts: #{fact_count}"

      if entity.metadata.present? && entity.metadata.any?
        puts "    Metadata: #{entity.metadata.to_json}"
      end
    end
  end

  def dump_facts
    puts "\n" + "=" * 70
    puts "FACTS"
    puts "=" * 70

    facts = FactDb::Models::Fact.includes(:entity_mentions, :fact_sources)
                                .order(:created_at)

    if facts.empty?
      puts "  (no fact records)"
      return
    end

    facts.each do |fact|
      puts "\n#{'-' * 60}"
      puts "ID: #{fact.id}"
      puts "Text: #{fact.text}"
      puts "Valid: #{fact.valid_at}#{" to #{fact.invalid_at}" if fact.invalid_at}"
      puts "Status: #{fact.status}"
      puts "Method: #{fact.extraction_method}"
      puts "Confidence: #{fact.confidence}"

      if fact.metadata.present?
        puts "Metadata: #{fact.metadata.to_json}"
      end

      # Entity mentions
      if fact.entity_mentions.any?
        puts "Mentions:"
        fact.entity_mentions.each do |mention|
          entity_name = mention.entity&.name || "(unknown)"
          puts "  - #{entity_name} (#{mention.mention_role}): \"#{mention.mention_text}\""
        end
      end

      # Sources
      if fact.fact_sources.any?
        puts "Sources:"
        fact.fact_sources.each do |fact_source|
          source_title = fact_source.source&.title || "(unknown)"
          puts "  - #{source_title} (#{fact_source.kind}, confidence: #{fact_source.confidence})"
        end
      end
    end
  end

  def dump_relationships
    puts "\n" + "=" * 70
    puts "RELATIONSHIPS"
    puts "=" * 70

    # Entity mention statistics
    puts "\nTop entities by mention count:"
    entity_mention_counts = FactDb::Models::Entity
      .joins(:entity_mentions)
      .group('fact_db_entities.id')
      .order(Arel.sql('count(*) DESC'))
      .limit(20)
      .count

    entity_ids = entity_mention_counts.keys
    entities_by_id = FactDb::Models::Entity.where(id: entity_ids).index_by(&:id)

    entity_mention_counts.each do |id, count|
      entity = entities_by_id[id]
      next unless entity

      puts "  #{entity.name.to_s.ljust(30)} (#{entity.kind.to_s.ljust(12)}) #{count.to_s.rjust(4)} mentions"
      if entity.all_aliases.any?
        puts "    Aliases: #{entity.all_aliases.join(', ')}"
      end
    end

    # Sources with most facts
    puts "\nSources by linked fact count:"
    source_facts = FactDb::Models::Source
      .joins(:fact_sources)
      .group('fact_db_sources.id', 'fact_db_sources.title')
      .order(Arel.sql('count(*) DESC'))
      .limit(10)
      .count

    source_facts.each do |(id, title), count|
      puts "  #{(title || 'untitled').to_s.ljust(40)} #{count.to_s.rjust(4)} facts"
    end
  end

  def search(term)
    puts "\n" + "=" * 70
    puts "SEARCH RESULTS: \"#{term}\""
    puts "=" * 70

    # Search entities
    puts "\nMatching Entities:"
    entities = FactDb::Models::Entity.where(
      "name ILIKE ? OR description ILIKE ?",
      "%#{term}%", "%#{term}%"
    ).order(:name)

    if entities.any?
      entities.each do |entity|
        puts "  #{entity.name} (#{entity.kind})"
        puts "    #{entity.description}" if entity.description.present?
      end
    else
      puts "  (no matching entities)"
    end

    # Search facts
    puts "\nMatching Facts:"
    facts = FactDb::Models::Fact.where(
      "text ILIKE ?", "%#{term}%"
    ).order(:created_at).limit(50)

    if facts.any?
      facts.each do |fact|
        puts "  [#{fact.id}] #{fact.text}"
      end
      puts "  (showing first 50 of #{FactDb::Models::Fact.where("text ILIKE ?", "%#{term}%").count})" if facts.count == 50
    else
      puts "  (no matching facts)"
    end

    # Search sources
    puts "\nMatching Sources:"
    sources = FactDb::Models::Source.where(
      "title ILIKE ? OR content ILIKE ?",
      "%#{term}%", "%#{term}%"
    ).order(:title).limit(20)

    if sources.any?
      sources.each do |source|
        puts "  [#{source.id}] #{source.title || '(untitled)'} (#{source.kind})"
      end
    else
      puts "  (no matching sources)"
    end
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  options = {}

  ARGV.each_with_index do |arg, i|
    case arg
    when "--summary"
      options[:summary] = true
    when "--entities"
      options[:entities] = true
    when "--facts"
      options[:facts] = true
    when "--sources"
      options[:sources] = true
    when "--search"
      options[:search] = ARGV[i + 1]
    when "--help", "-h"
      puts <<~HELP
        FactDb Database Dump Utility

        Usage:
          ruby dump_database.rb                # Full dump
          ruby dump_database.rb --summary      # Summary statistics only
          ruby dump_database.rb --entities     # Entities only
          ruby dump_database.rb --facts        # Facts only
          ruby dump_database.rb --sources      # Sources only
          ruby dump_database.rb --search TERM  # Search facts/entities/sources

        Environment:
          DATABASE_URL  # PostgreSQL connection URL (default: postgres://USER@localhost/fact_db_demo)
      HELP
      exit 0
    end
  end

  DatabaseDumper.new.run(options)
end
