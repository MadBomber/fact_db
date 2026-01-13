#!/usr/bin/env ruby
# frozen_string_literal: true

# Ingest Demo for FactDb
#
# This example demonstrates building a fact database from a directory of markdown files
# using automatic entity and fact extraction:
# - Parsing markdown files with optional YAML frontmatter
# - Using LLM-based extraction to identify entities and facts
# - Automatic entity resolution and deduplication
# - Progressive entity discovery from text
#
# Usage:
#   ruby ingest_demo.rb <directory>           # Build/update database from directory
#   ruby ingest_demo.rb <file.md>             # Process a single markdown file
#   ruby ingest_demo.rb <path> --rebuild      # Drop and rebuild from scratch
#   ruby ingest_demo.rb --stats               # Show statistics only

require_relative "utilities"
require_relative "ingest_reporter"
require "yaml"
require "debug_me"
include DebugMe
require "amazing_print"

# Note: CLI tool - uses cli_setup! which does NOT reset database
# Use --rebuild flag to explicitly reset

class IngestDemo
  def initialize(path:, rebuild: false, count: nil, reporter: nil)
    @path = path
    @is_file = File.file?(@path)
    @directory = @is_file ? File.dirname(@path) : @path
    @rebuild = rebuild
    @count = count
    @reporter = reporter || IngestReporter.new
    setup_factdb
  end

  def run
    unless File.exist?(@path)
      puts "Error: Path not found: #{@path}"
      exit 1
    end

    if @is_file && !@path.end_with?(".md")
      puts "Error: File must be a markdown (.md) file: #{@path}"
      exit 1
    end

    if @rebuild
      puts "Rebuilding database from scratch..."
      clear_all_data
    end

    puts "=" * 60
    puts "Document Ingest Demo - FactDb (Automatic Extraction)"
    puts "=" * 60
    puts @is_file ? "Source file: #{@path}" : "Source directory: #{@directory}"
    puts "Extractor: #{@extractor.class.name.split('::').last}"
    puts

    process_markdown_files
    show_statistics
    demonstrate_queries

    puts "\n" + "=" * 60
    puts "Document Ingest Complete!"
    puts "=" * 60
  end

  def show_statistics_only
    puts "=" * 60
    puts "Database Statistics"
    puts "=" * 60

    show_statistics
  end

  private

  def setup_factdb
    # Ensure demo environment is set
    DemoUtilities.ensure_demo_environment!
    DemoUtilities.require_fact_db!

    log_path = File.join(__dir__, "#{File.basename(__FILE__, '.rb')}.log")

    FactDb.configure do |config|
      config.default_extractor = :llm
      config.logger = Logger.new(File.open(log_path, 'w'))

      # Configure LLM client - uses environment variables by default
      # Supports: ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, etc.
      provider = ENV.fetch("FACT_DB_LLM_PROVIDER", "anthropic").to_sym
      config.llm_client = FactDb::LLM::Adapter.new(provider: provider)
    end

    FactDb::Database.migrate!

    @facts = FactDb.new
    @entity_service = @facts.entity_service
    @fact_service = @facts.fact_service
    @source_service = @facts.source_service
    @extractor = FactDb::Extractors::Base.for(:llm)
  end

  def clear_all_data
    puts "Clearing all data from database..."

    # Clear in order respecting foreign key constraints
    FactDb::Models::FactSource.delete_all
    FactDb::Models::EntityMention.delete_all
    FactDb::Models::Fact.delete_all
    FactDb::Models::EntityAlias.delete_all
    FactDb::Models::Entity.delete_all
    FactDb::Models::Source.delete_all

    puts "  All data cleared"
  end

  def clear_directory_data
    puts "Clearing existing data from this directory..."

    # Find and remove sources from this directory
    dir_name = File.basename(@directory)
    directory_sources = FactDb::Models::Source.where("metadata->>'source_directory' = ?", dir_name)
    source_ids = directory_sources.pluck(:id)

    if source_ids.any?
      FactDb::Models::FactSource.where(source_id: source_ids).delete_all
      directory_sources.delete_all
      puts "  Removed #{source_ids.count} source records"
    end

    puts "  Data cleared"
  end

  def file_already_processed?(file_path)
    filename = File.basename(file_path, ".md")
    FactDb::Models::Source.exists?(title: filename)
  end

  def process_markdown_files
    if @is_file
      all_files = [@path]
    else
      all_files = Dir.glob(File.join(@directory, "*.md")).sort
    end

    # Filter to only unprocessed files
    unprocessed_files = all_files.reject { |f| file_already_processed?(f) }
    already_processed = all_files.count - unprocessed_files.count

    files = @count ? unprocessed_files.first(@count) : unprocessed_files

    @reporter.start_ingestion(
      total_files: files.count,
      source_path: @is_file ? @path : @directory
    )
    @reporter.report_already_processed(already_processed)

    if files.empty?
      @reporter.no_files_to_process
      return
    end

    files.each_with_index do |file, index|
      process_markdown_file(file, index + 1, files.count)
    end

    @reporter.finish_ingestion
  end

  def process_markdown_file(file_path, file_index, total_files)
    filename = File.basename(file_path, ".md")
    content_text = File.read(file_path)

    @reporter.file_started(filename, file_index, total_files)

    # Parse frontmatter and content
    frontmatter, body = parse_frontmatter(content_text)

    # Create source record for the document
    source = find_or_create_source(filename, content_text, frontmatter)

    # Split into paragraphs/sections for processing
    sections = parse_sections(body)

    # Process sections with LLM extraction
    stats = process_sections_with_extraction(filename, sections, source)

    @reporter.file_completed(**stats)
  end

  def parse_frontmatter(content)
    if content.start_with?("---")
      parts = content.split("---", 3)
      if parts.length >= 3
        frontmatter = YAML.safe_load(parts[1]) rescue {}
        body = parts[2]
        return [frontmatter, body]
      end
    end
    [{}, content]
  end

  def find_or_create_source(filename, content_text, frontmatter)
    title = frontmatter["title"] || filename

    existing = FactDb::Models::Source.find_by(title: title)
    return existing if existing

    @source_service.create(
      content_text,
      kind: :document,
      title: title,
      metadata: frontmatter.merge(
        source_directory: File.basename(@directory),
        source_file: filename
      )
    )
  end

  def parse_sections(body)
    sections = []
    current_section = { heading: nil, text: "", start_line: 1, end_line: 1 }
    line_number = 0

    body.each_line do |line|
      line_number += 1
      line_stripped = line.strip

      # Detect markdown headers
      if line_stripped =~ /^(#+)\s+(.+)$/
        # Save previous section if it has content
        if current_section[:text].strip.length > 0
          current_section[:end_line] = line_number - 1
          sections << current_section
        end
        current_section = { heading: $2.strip, text: "", start_line: line_number, end_line: line_number }
      elsif !line_stripped.empty? && line_stripped != "---"
        current_section[:text] += " " unless current_section[:text].empty?
        current_section[:text] += line_stripped
        current_section[:end_line] = line_number
      end
    end

    # Add final section
    if current_section[:text].strip.length > 0
      current_section[:end_line] = line_number
      sections << current_section
    end

    sections
  end

  def process_sections_with_extraction(filename, sections, source)
    stats = { facts: 0, entities: 0, skipped: 0, errors: 0 }
    total_sections = sections.count

    sections.each_with_index do |section, index|
      section_text = clean_text(section[:text])
      next if section_text.empty? || section_text.length < 10

      section_ref = section[:heading] || "Section #{index + 1}"
      @reporter.section_started(section_ref, index + 1, total_sections)

      # Skip if facts already exist for this section
      fact_identifier = "#{filename}: #{section_ref}"
      existing = FactDb::Models::Fact.where("metadata->>'section_ref' = ?", fact_identifier).first
      if existing
        stats[:skipped] += 1
        @reporter.section_skipped(section_ref)
        @reporter.section_completed
        next
      end

      begin
        # Extract atomic facts from section text with progress feedback
        extracted_facts = extract_with_progress(section_text)

        section_facts = 0
        section_entities = 0

        extracted_facts.each do |fact_data|
          # Resolve/create entities from mentions and build mention references
          mentions = []
          (fact_data[:mentions] || []).each do |mention_data|
            entity = @entity_service.resolve_or_create(
              mention_data[:name],
              kind: normalize_kind(mention_data[:kind]),
              aliases: mention_data[:aliases] || [],
              description: "Extracted from #{filename}"
            )

            # Add any aliases that weren't already added during creation
            (mention_data[:aliases] || []).each do |alias_text|
              next if alias_text.to_s.strip.empty?
              next if entity.name.downcase == alias_text.to_s.strip.downcase
              next if entity.all_aliases.map(&:downcase).include?(alias_text.to_s.strip.downcase)

              entity.add_alias(alias_text.to_s.strip)
            end

            mentions << {
              entity_id: entity.id,
              role: mention_data[:role] || determine_role(mention_data[:type]),
              text: mention_data[:name]
            }
            section_entities += 1
          end

          # Create the atomic fact
          fact_metadata = {
            source_file: filename,
            section_heading: section[:heading],
            section_ref: fact_identifier,
            line_start: section[:start_line],
            line_end: section[:end_line]
          }.compact

          fact = @fact_service.create(
            fact_data[:text],
            valid_at: fact_data[:valid_at] || Date.today,
            invalid_at: fact_data[:invalid_at],
            extraction_method: :llm,
            confidence: fact_data[:confidence] || 0.8,
            mentions: mentions.uniq { |m| m[:entity_id] },
            metadata: fact_metadata
          )

          fact.add_source(source: source, kind: :primary, confidence: 1.0)
          section_facts += 1
        end

        @reporter.extraction_completed(facts_count: section_facts, entities_count: section_entities)
        stats[:facts] += section_facts
        stats[:entities] += section_entities

      rescue StandardError => e
        debug_me { [:section_ref, :e] }
        @reporter.error_occurred(e, context: section_ref)
        stats[:errors] += 1
      end

      @reporter.section_completed
    end

    stats
  end

  # Extract facts with periodic progress updates
  def extract_with_progress(text)
    @reporter.extraction_started

    # Run extraction in a thread so we can update progress
    result = nil
    extraction_thread = Thread.new do
      result = @extractor.extract(text)
    end

    # Update progress while extraction runs
    while extraction_thread.alive?
      @reporter.extraction_progress
      sleep 0.15
    end

    extraction_thread.join
    result
  end

  def clean_text(text)
    text
      .gsub(/\*\*/, "")           # Remove bold markers
      .gsub(/\*/, "")             # Remove italic markers
      .gsub(/`[^`]+`/, "")        # Remove inline code
      .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')  # Convert links to text
      .gsub(/#+\s*/, "")          # Remove header markers
      .strip
  end

  def determine_role(entity_type)
    # Valid roles: subject, object, location, temporal, instrument, beneficiary
    case entity_type.to_s
    when "person" then :subject
    when "place" then :location
    when "organization" then :object
    when "event" then :temporal
    else :subject
    end
  end

  def normalize_kind(kind)
    return :concept if kind.nil?

    kind_sym = kind.to_s.downcase.to_sym
    valid_kinds = FactDb::Models::Entity::ENTITY_KINDS.map(&:to_sym)

    valid_kinds.include?(kind_sym) ? kind_sym : :other
  end

  def show_statistics
    puts "\n--- Database Statistics ---\n"

    puts "Sources:"
    ap @source_service.stats

    puts "\nEntities:"
    ap @entity_service.stats

    puts "\nFacts:"
    ap @fact_service.stats

    # Directory-specific stats if available
    if @directory
      dir_name = File.basename(@directory)
      dir_sources = FactDb::Models::Source.where("metadata->>'source_directory' = ?", dir_name).count
      dir_facts = FactDb::Models::Fact.where("metadata->>'source_file' IS NOT NULL").count

      puts "\nDirectory '#{dir_name}':"
      puts "  Documents loaded: #{dir_sources}"
      puts "  Facts extracted: #{dir_facts}"
    end

    # Show discovered entities by kind
    puts "\nDiscovered entities by kind:"
    ap FactDb::Models::Entity.group(:kind).count
  end

  def demonstrate_queries
    puts "\n--- Sample Queries ---\n"

    # Show some discovered entities
    puts "\nRecently discovered entities (last 10):"
    recent_entities = FactDb::Models::Entity.order(created_at: :desc).limit(10)
    recent_entities.each do |entity|
      fact_count = entity.facts.count
      puts "  #{entity.name} (#{entity.kind}) - #{fact_count} mentions"
    end

    # Show recent facts
    puts "\nRecent facts (last 5):"
    recent_facts = FactDb::Models::Fact.order(created_at: :desc).limit(5)
    recent_facts.each do |fact|
      puts "  #{fact.text[0..80]}..."
    end
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  options = { rebuild: false, path: nil, count: nil, reporter: nil }

  args = ARGV.dup
  while arg = args.shift
    case arg
    when "--rebuild"
      options[:rebuild] = true
    when "--count"
      options[:count] = args.shift.to_i
    when "--quiet", "-q"
      options[:reporter] = QuietReporter.new
    when "--verbose", "-v"
      options[:reporter] = VerboseReporter.new
    when "--stats"
      IngestDemo.new(path: ".").show_statistics_only
      exit 0
    when "--help", "-h"
      puts <<~HELP
        Document Ingest Demo for FactDb (Automatic Extraction)

        Usage:
          ruby ingest_demo.rb <directory>           # Build/update database from directory
          ruby ingest_demo.rb <file.md>             # Process a single markdown file
          ruby ingest_demo.rb <path> --rebuild      # Drop and rebuild from scratch
          ruby ingest_demo.rb <directory> --count 3 # Process only first 3 files
          ruby ingest_demo.rb --stats               # Show statistics only

        Options:
          --rebuild       Clear existing data and rebuild from scratch
          --count <n>     Process only the first n files (for testing, directory only)
          --quiet, -q     Minimal output (good for scripts/CI)
          --verbose, -v   Detailed output with section-level progress
          --stats         Show database statistics only
          --help, -h      Show this help message

        Environment variables:
          FACT_DB_LLM_PROVIDER  # LLM provider (anthropic, openai, gemini, ollama)
          ANTHROPIC_API_KEY     # API key for Anthropic
          OPENAI_API_KEY        # API key for OpenAI
          DATABASE_URL          # PostgreSQL connection URL

        Accepts either a directory containing markdown (.md) files or a single
        markdown file. Files may optionally include YAML frontmatter between
        --- delimiters at the start of the file.

        Reporter classes (IngestReporter, QuietReporter, VerboseReporter) can be
        used directly in your own applications for custom progress handling.
      HELP
      exit 0
    else
      options[:path] = arg unless arg.start_with?("-")
    end
  end

  unless options[:path]
    puts "Error: Please specify a directory or markdown file"
    puts "Usage: ruby ingest_demo.rb <directory|file.md>"
    puts "Run 'ruby ingest_demo.rb --help' for more information"
    exit 1
  end

  IngestDemo.new(**options).run
end
