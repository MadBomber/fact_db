#!/usr/bin/env ruby
# frozen_string_literal: true

# Prove It - Source Evidence Viewer for FactDb
#
# Displays fact records along with their original source text evidence.
#
# Usage:
#   ruby prove_it.rb <fact_id> [fact_id...]    # Show facts with source evidence
#   ruby prove_it.rb --last <n>                # Show last n facts
#   ruby prove_it.rb --search <term>           # Search facts and show evidence

require_relative "utilities"

# Note: CLI tool - uses cli_setup! which does NOT reset database

class ProveItDemo
  def initialize
    setup_factdb
  end

  def run(fact_ids)
    puts "=" * 70
    puts "Prove It - Source Evidence Viewer"
    puts "=" * 70
    puts

    if fact_ids.empty?
      puts "No fact IDs provided."
      puts "Usage: ruby prove_it.rb <fact_id> [fact_id...]"
      puts "       ruby prove_it.rb --last <n>"
      puts "       ruby prove_it.rb --search <term>"
      return
    end

    fact_ids.each do |id|
      display_fact(id)
    end
  end

  def run_last(count)
    puts "=" * 70
    puts "Prove It - Last #{count} Facts"
    puts "=" * 70
    puts

    facts = FactDb::Models::Fact.order(created_at: :desc).limit(count)

    if facts.empty?
      puts "No facts found in database."
      return
    end

    facts.each do |fact|
      display_fact_record(fact)
    end
  end

  def run_search(term)
    puts "=" * 70
    puts "Prove It - Search: \"#{term}\""
    puts "=" * 70
    puts

    facts = FactDb::Models::Fact.where("fact_text ILIKE ?", "%#{term}%").limit(20)

    if facts.empty?
      puts "No facts found matching \"#{term}\"."
      return
    end

    puts "Found #{facts.count} matching facts:\n\n"

    facts.each do |fact|
      display_fact_record(fact)
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

  def display_fact(id)
    fact = FactDb::Models::Fact.find_by(id: id)

    if fact.nil?
      puts "Fact ID #{id} not found."
      puts "-" * 70
      puts
      return
    end

    display_fact_record(fact)
  end

  def display_fact_record(fact)
    puts "-" * 70
    puts "FACT ID: #{fact.id}"
    puts "-" * 70
    puts
    puts "Text: #{fact.fact_text}"
    puts
    puts "Valid: #{fact.valid_at}#{" to #{fact.invalid_at}" if fact.invalid_at}"
    puts "Status: #{fact.status}"
    puts "Extraction: #{fact.extraction_method}"
    puts "Confidence: #{fact.confidence}"
    puts

    if fact.metadata.present?
      puts "Metadata:"
      fact.metadata.each do |key, value|
        puts "  #{key}: #{value}"
      end
      puts
    end

    if fact.entity_mentions.any?
      puts "Entities:"
      fact.entity_mentions.includes(:entity).each do |mention|
        entity_name = mention.entity&.name || "(unknown)"
        puts "  - #{entity_name} (#{mention.mention_role})"
      end
      puts
    end

    evidence = fact.prove_it
    if evidence
      # Show focused lines (most relevant)
      if evidence[:focused_lines].present?
        line_nums = evidence[:focused_line_numbers].join(", ")
        puts "FOCUSED EVIDENCE (lines #{line_nums}):"
        puts "-" * 40
        puts evidence[:focused_lines]
        puts "-" * 40
        puts
        puts "Key terms matched: #{evidence[:key_terms].first(10).join(", ")}"
      else
        # Show full section context
        puts
        puts "FULL SECTION (lines #{fact.metadata["line_start"]}-#{fact.metadata["line_end"]}):"
        puts "-" * 40
        puts evidence[:full_section]
        puts "-" * 40
      end
    else
      puts "SOURCE EVIDENCE: Not available"
      puts "  (Missing line numbers or source content)"
    end

    puts
    puts
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  if ARGV.empty? || ARGV.include?("--help") || ARGV.include?("-h")
    puts <<~HELP
           Prove It - Source Evidence Viewer for FactDb

           Displays fact records along with their original source text evidence.

           Usage:
             ruby prove_it.rb <fact_id> [fact_id...]    # Show specific facts
             ruby prove_it.rb --last <n>                # Show last n facts
             ruby prove_it.rb --search <term>           # Search facts by text

           Examples:
             ruby prove_it.rb 123 456 789
             ruby prove_it.rb --last 5
             ruby prove_it.rb --search "Stephen"

           Environment:
             DATABASE_URL  # PostgreSQL connection URL
         HELP
    exit 0
  end

  demo = ProveItDemo.new

  if ARGV[0] == "--last"
    count = (ARGV[1] || 10).to_i
    demo.run_last(count)
  elsif ARGV[0] == "--search"
    term = ARGV[1..-1].join(" ")
    if term.empty?
      puts "Error: Please provide a search term"
      exit 1
    end
    demo.run_search(term)
  else
    fact_ids = ARGV.map(&:to_i).reject(&:zero?)
    demo.run(fact_ids)
  end
end
