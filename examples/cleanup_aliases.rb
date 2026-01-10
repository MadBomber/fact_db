#!/usr/bin/env ruby
# frozen_string_literal: true

# Cleanup script to remove invalid aliases (pronouns, generic terms, etc.)
# from existing entities in the database.
#
# Usage:
#   ruby examples/cleanup_aliases.rb           # Dry run (shows what would be deleted)
#   ruby examples/cleanup_aliases.rb --execute # Actually delete invalid aliases

require_relative "../lib/fact_db"

# Configure the database connection
FactDb.configure do |config|
  config.logger = Logger.new("/dev/null")
end

# Establish connection
FactDb::Database.establish_connection!

class AliasCleanup
  attr_reader :dry_run, :stats

  def initialize(dry_run: true)
    @dry_run = dry_run
    @stats = {
      entities_checked: 0,
      aliases_checked: 0,
      aliases_removed: 0,
      aliases_by_reason: Hash.new(0)
    }
  end

  def run
    puts_header
    cleanup_aliases
    print_summary
  end

  private

  def puts_header
    mode = dry_run ? "DRY RUN" : "EXECUTE"
    puts <<~HEADER

      ============================================
      Alias Cleanup Script - #{mode}
      ============================================

    HEADER
  end

  def cleanup_aliases
    FactDb::Models::Entity.not_merged.find_each do |entity|
      @stats[:entities_checked] += 1
      process_entity(entity)
    end
  end

  def process_entity(entity)
    invalid_aliases = []

    entity.aliases.each do |alias_record|
      @stats[:aliases_checked] += 1

      unless FactDb::Validation::AliasFilter.valid?(alias_record.alias_text, canonical_name: entity.canonical_name)
        reason = FactDb::Validation::AliasFilter.rejection_reason(alias_record.alias_text, canonical_name: entity.canonical_name)
        invalid_aliases << { record: alias_record, reason: reason }
        @stats[:aliases_by_reason][reason] += 1
      end
    end

    return if invalid_aliases.empty?

    report_invalid_aliases(entity, invalid_aliases)
    remove_aliases(invalid_aliases) unless dry_run
  end

  def report_invalid_aliases(entity, invalid_aliases)
    puts "Entity: #{entity.canonical_name} (#{entity.entity_type}, ID: #{entity.id})"

    invalid_aliases.each do |item|
      puts "  - Removing alias: \"#{item[:record].alias_text}\" (#{item[:reason]})"
      @stats[:aliases_removed] += 1
    end

    puts
  end

  def remove_aliases(invalid_aliases)
    invalid_aliases.each do |item|
      item[:record].destroy
    end
  end

  def print_summary
    puts <<~SUMMARY

      ============================================
      Summary
      ============================================
      Entities checked:    #{@stats[:entities_checked]}
      Aliases checked:     #{@stats[:aliases_checked]}
      Aliases to remove:   #{@stats[:aliases_removed]}

    SUMMARY

    if @stats[:aliases_by_reason].any?
      puts "Breakdown by reason:"
      @stats[:aliases_by_reason].sort_by { |_, count| -count }.each do |reason, count|
        puts "  #{reason}: #{count}"
      end
      puts
    end

    if dry_run && @stats[:aliases_removed] > 0
      puts "Run with --execute to actually delete these aliases."
      puts
    end
  end
end

# Parse command line arguments
dry_run = !ARGV.include?("--execute")

# Run the cleanup
cleanup = AliasCleanup.new(dry_run: dry_run)
cleanup.run
