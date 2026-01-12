#!/usr/bin/env ruby
# frozen_string_literal: true

# RAG Feedback Loop Demo for FactDb
#
# This example demonstrates a Retrieval-Augmented Generation (RAG) workflow
# that feeds LLM-generated knowledge back into the fact database:
#
# 1. Takes a user prompt from the command line
# 2. Retrieves relevant facts from the database as context
# 3. Enhances the prompt with retrieved context
# 4. Sends the enhanced prompt to an LLM for processing
# 5. Ingests the LLM response back into the fact database
# 6. Reports on new facts discovered from the LLM output
#
# This creates a "knowledge compounding" effect where each query can
# expand the database with synthesized knowledge.
#
# Usage:
#   ruby 130_rag_feedback_loop.rb "What are the key events in Acts chapter 5?"
#   ruby 130_rag_feedback_loop.rb --verbose "Tell me about Ananias and Sapphira"
#   ruby 130_rag_feedback_loop.rb --dry-run "Summarize Peter's role in Acts"
#   ruby 130_rag_feedback_loop.rb --context-only "Who was Stephen?"
#
# Options:
#   --verbose         Show detailed processing steps
#   --dry-run         Show enhanced prompt but don't call LLM or ingest
#   --context-only    Show retrieved context without LLM processing
#   --limit N         Maximum facts to retrieve for context (default: 15)
#   --format FORMAT   Context format: text, json (default: text)

require_relative "utilities"
require "optparse"
require "set"
require "debug_me"
include DebugMe

class RagFeedbackLoop
  CONTEXT_FORMATS = %i[text json].freeze

  def initialize(options = {})
    @verbose = options[:verbose] || false
    @dry_run = options[:dry_run] || false
    @context_only = options[:context_only] || false
    @limit = options[:limit] || 15
    @min_relevance = options[:min_relevance] || 0.0
    @format = options[:format] || :text
    @stats_before = {}
    @stats_after = {}
    @filtered_count = 0
    @scored_context = []
    @duplicate_facts = []
    setup_factdb
  end

  def run(prompt)
    log_header(prompt)
    capture_stats_before

    # Step 1: Retrieve relevant context from the database
    log_step("Step 1", "Retrieving relevant facts from database...")
    context_facts = retrieve_context(prompt)

    if context_facts.empty?
      puts "\nNo existing context found in database for this prompt."
      puts "The LLM will respond without fact database context."
      puts
    else
      log_step("Retrieved Facts", "#{context_facts.size} facts found")
      display_context(context_facts) if @verbose
    end

    # Step 2: Build enhanced prompt with context
    log_step("Step 2", "Building enhanced prompt with context...")
    enhanced_prompt = build_enhanced_prompt(prompt, context_facts)

    if @dry_run || @context_only
      display_enhanced_prompt(enhanced_prompt)
      return if @context_only

      puts "\n[DRY RUN] Skipping LLM call and ingestion"
      return
    end

    # Step 3: Send to LLM for processing
    log_step("Step 3", "Sending enhanced prompt to LLM...")
    llm_response = call_llm(enhanced_prompt)

    if llm_response.nil? || llm_response.strip.empty?
      puts "\nError: LLM returned empty response"
      return
    end

    display_llm_response(llm_response)

    # Step 4: Ingest LLM response into database
    log_step("Step 4", "Ingesting LLM response into fact database...")
    content = ingest_response(prompt, llm_response)

    # Step 5: Extract facts from the response
    log_step("Step 5", "Extracting facts from LLM response...")
    extracted_facts = extract_facts(content, llm_response)

    # Step 6: Report on new entries
    capture_stats_after
    report_new_entries(extracted_facts)

    demo_footer("RAG Feedback Loop Complete!")
  end

  private

  def setup_factdb
    DemoUtilities.ensure_demo_environment!
    DemoUtilities.require_fact_db!

    log_path = File.join(__dir__, "#{File.basename(__FILE__, '.rb')}.log")

    FactDb.configure do |config|
      config.default_extractor = :llm
      config.logger = Logger.new(log_path)

      # Configure LLM client
      provider = ENV.fetch("FACT_DB_LLM_PROVIDER", "anthropic").to_sym
      config.llm_client = FactDb::LLM::Adapter.new(provider: provider)
    end

    FactDb::Database.establish_connection!

    @facts = FactDb.new
    @entity_service = @facts.entity_service
    @fact_service = @facts.fact_service
    @source_service = @facts.source_service
    @extractor = FactDb::Extractors::Base.for(:llm)
    @llm_client = FactDb.config.llm_client
  end

  def capture_stats_before
    @stats_before = {
      facts: FactDb::Models::Fact.count,
      entities: FactDb::Models::Entity.count,
      sources: FactDb::Models::Source.count
    }
  end

  def capture_stats_after
    @stats_after = {
      facts: FactDb::Models::Fact.count,
      entities: FactDb::Models::Entity.count,
      sources: FactDb::Models::Source.count
    }
  end

  def retrieve_context(prompt)
    facts = []
    gather_limit = @limit * 3  # Gather more candidates for ranking

    # Strategy 1: Enhanced entity resolution (includes bigrams, key terms, fuzzy matching)
    @resolved_entities = resolve_entities_enhanced(prompt)

    log_step("Resolved entities", @resolved_entities.map(&:name)) if @verbose

    # Get facts for resolved entities (include both canonical and synthesized)
    @resolved_entities.each do |entity|
      # current_facts only returns canonical status - we need synthesized too
      entity_facts = FactDb::Models::Fact
                       .joins(:entity_mentions)
                       .where(entity_mentions: { entity_id: entity.id })
                       .where(status: %w[canonical synthesized corroborated])
                       .currently_valid
                       .limit(gather_limit)
      facts.concat(entity_facts.to_a)
    end

    # Strategy 2: Full-text search (include synthesized facts)
    search_facts = @fact_service.search(prompt, status: nil, limit: gather_limit)
    facts.concat(search_facts.to_a)

    # Strategy 3: Search key terms (include synthesized facts)
    extract_key_terms(prompt).each do |term|
      term_facts = @fact_service.search(term, status: nil, limit: 10)
      facts.concat(term_facts.to_a)
    end

    # Strategy 4: Semantic search if available
    begin
      semantic_facts = @fact_service.semantic_search(prompt, limit: gather_limit)
      facts.concat(semantic_facts.to_a) if semantic_facts.any?
    rescue StandardError
      # Semantic search not available
    end

    # Deduplicate candidates
    unique_facts = facts.uniq(&:id)

    # Rank by relevance and return top N (now returns array of {fact:, score:, signals:})
    @scored_context = rank_facts_by_relevance(prompt, unique_facts)
    @scored_context.map { |sf| sf[:fact] }
  end

  # Rank facts by relevance to the query using multiple signals
  # Returns array of hashes with :fact, :score, and :signals keys
  def rank_facts_by_relevance(query, facts)
    return [] if facts.empty?

    query_terms = extract_key_terms(query)
    entity_names = @resolved_entities.flat_map do |e|
      [e.name.downcase] + e.all_aliases.map(&:downcase)
    end

    # Compute ts_rank scores for full-text relevance
    ts_scores = compute_ts_rank_scores(query, facts.map(&:id))

    scored_facts = facts.map do |fact|
      text_lower = fact.text.downcase
      signals = {}

      # Signal 1: PostgreSQL ts_rank (full-text search relevance) - weight 0.30
      ts_score = ts_scores[fact.id] || 0.0
      signals[:ts_rank] = ts_score * 0.30

      # Signal 2: Entity mention score - weight 0.25
      entity_match_count = entity_names.count { |name| text_lower.include?(name) }
      signals[:entity] = [entity_match_count * 0.125, 0.25].min

      # Signal 3: Query term overlap - weight 0.20
      term_matches = query_terms.count { |term| text_lower.include?(term.downcase) }
      signals[:terms] = query_terms.empty? ? 0 : (term_matches.to_f / query_terms.size) * 0.20

      # Signal 4: Fact confidence - weight 0.15
      signals[:confidence] = (fact.confidence || 0.5) * 0.15

      # Signal 5: Prefer canonical facts over synthesized - weight 0.10
      signals[:status] = case fact.status
                         when "canonical" then 0.10
                         when "corroborated" then 0.08
                         when "synthesized" then 0.05
                         else 0.03
                         end

      total_score = signals.values.sum

      { fact: fact, score: total_score, signals: signals }
    end

    # Sort by score descending
    sorted = scored_facts.sort_by { |f| -f[:score] }

    # Filter by minimum relevance threshold
    if @min_relevance > 0
      before_count = sorted.size
      sorted = sorted.select { |f| f[:score] >= @min_relevance }
      @filtered_count = before_count - sorted.size
    end

    sorted.first(@limit)
  end

  # Compute PostgreSQL ts_rank scores for full-text search relevance
  def compute_ts_rank_scores(query, fact_ids)
    return {} if fact_ids.empty? || query.strip.empty?

    sql = <<~SQL
      SELECT id,
             ts_rank_cd(to_tsvector('english', text),
                        plainto_tsquery('english', ?),
                        32) as rank
      FROM fact_db_facts
      WHERE id IN (?)
    SQL

    results = ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql([sql, query, fact_ids])
    )

    scores = {}
    max_score = 0.0

    results.each do |row|
      score = row["rank"].to_f
      scores[row["id"]] = score
      max_score = score if score > max_score
    end

    # Normalize scores to 0-1 range
    max_score > 0 ? scores.transform_values { |s| s / max_score } : scores
  rescue StandardError => e
    log_step("ts_rank error", e.message) if @verbose
    {}
  end

  def extract_entity_candidates(query)
    candidates = []

    # Capitalized words/phrases
    query.scan(/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b/).each do |match|
      candidates << match unless stop_words.include?(match.downcase)
    end

    # Possessive forms
    query.scan(/\b([A-Z][a-z]+)'s\b/).flatten.each do |match|
      candidates << match
    end

    # Quoted strings
    query.scan(/"([^"]+)"/).flatten.each do |match|
      candidates << match
    end

    candidates.uniq
  end

  # Simplified entity resolution - lets the database do the heavy lifting
  def resolve_entities_enhanced(query)
    entities = []

    # Strategy 1: Rule-based extraction for proper nouns (capitalized words)
    candidates = extract_entity_candidates(query)
    log_step("Capitalized candidates", candidates) if @verbose

    candidates.each do |name|
      resolved = @entity_service.resolve(name)
      entities << resolved.entity if resolved
    end

    # Strategy 2: Full query search - database LIKE matching handles phrases
    log_step("Full query search", query) if @verbose
    search_results = @entity_service.search(query, limit: 5)
    entities.concat(search_results.to_a)

    # Strategy 3: Fuzzy search - database pg_trgm handles misspellings
    log_step("Fuzzy search", query) if @verbose
    fuzzy_results = @entity_service.fuzzy_search(query, threshold: 0.3, limit: 5)
    entities.concat(fuzzy_results)

    resolved = entities.uniq(&:id)
    log_step("Resolved entities", resolved.map(&:name)) if @verbose
    resolved
  end

  def extract_key_terms(query)
    query.downcase
         .gsub(/[^a-z\s']/, " ")
         .split
         .reject { |w| w.length < 3 || stop_words.include?(w) }
         .uniq
  end

  def stop_words
    %w[who what where when why how is was were are the a an and or but
       to of in for on with at by from as tell me about can could would
       should will shall may might must]
  end

  def build_enhanced_prompt(user_prompt, context_facts)
    context_text = format_context(context_facts)

    <<~PROMPT
      You are a knowledgeable assistant with access to a fact database. Use the provided context to inform your response, but also feel free to synthesize and expand upon the information with related knowledge.

      Your response should:
      1. Directly address the user's question
      2. Include specific facts, names, dates, and details where relevant
      3. Make connections between related pieces of information
      4. Present information in clear, atomic statements that can be extracted as individual facts

      #{context_section(context_text)}

      USER QUESTION: #{user_prompt}

      Please provide a comprehensive response with specific details and facts:
    PROMPT
  end

  def context_section(context_text)
    if context_text.strip.empty?
      "CONTEXT: No existing facts found in the database for this topic."
    else
      <<~CONTEXT
        CONTEXT FROM FACT DATABASE:
        #{context_text}
      CONTEXT
    end
  end

  def format_context(facts)
    return "" if facts.empty?

    case @format
    when :json
      format_context_json(facts)
    else
      format_context_text(facts)
    end
  end

  def format_context_text(facts)
    lines = []
    facts.each_with_index do |fact, idx|
      # Get entity mentions for context
      entities = fact.entity_mentions.map do |m|
        "#{m.entity.name} (#{m.entity.type})"
      end.uniq

      lines << "#{idx + 1}. #{fact.text}"
      lines << "   Entities: #{entities.join(', ')}" if entities.any?
      lines << "   Valid from: #{fact.valid_at}" if fact.valid_at
    end
    lines.join("\n")
  end

  def format_context_json(facts)
    require "json"
    data = facts.map do |fact|
      {
        text: fact.text,
        entities: fact.entity_mentions.map { |m| m.entity.name },
        valid_at: fact.valid_at&.to_s,
        confidence: fact.confidence
      }
    end
    JSON.pretty_generate(data)
  end

  def call_llm(prompt)
    unless @llm_client
      puts "Error: LLM client not configured"
      puts "Set ANTHROPIC_API_KEY, OPENAI_API_KEY, or configure via FactDb.configure"
      return nil
    end

    with_spinner("Waiting for LLM response...") do
      @llm_client.chat(prompt)
    end
  rescue StandardError => e
    debug_me { [:e] }
    puts "Error calling LLM: #{e.message}"
    nil
  end

  def ingest_response(original_prompt, llm_response)
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    title = "RAG Response: #{original_prompt[0..50]}..."

    @source_service.create(
      llm_response,
      type: :document,
      title: title,
      metadata: {
        source_type: "rag_synthesis",
        original_prompt: original_prompt,
        generated_at: timestamp,
        llm_provider: @llm_client&.provider&.to_s,
        llm_model: @llm_client&.model
      }
    )
  end

  def extract_facts(content, response_text)
    extracted_facts = []
    @duplicate_facts = []
    response_lines = response_text.lines

    begin
      # Use the LLM extractor to find atomic facts
      raw_facts = with_spinner("Extracting atomic facts...") do
        @extractor.extract(response_text)
      end

      log_step("Raw extracted facts", "#{raw_facts.size} facts identified") if @verbose

      raw_facts.each do |fact_data|
        # Check for duplicate before creating
        existing_fact = find_duplicate_fact(fact_data[:text])
        if existing_fact
          @duplicate_facts << { extracted_text: fact_data[:text], existing_fact: existing_fact }
          next
        end

        # Resolve/create entities from mentions
        mentions = []
        (fact_data[:mentions] || []).each do |mention_data|
          entity = @entity_service.resolve_or_create(
            mention_data[:name],
            type: mention_data[:type] || :concept,
            aliases: mention_data[:aliases] || [],
            description: "Extracted from RAG synthesis"
          )

          mentions << {
            entity_id: entity.id,
            role: mention_data[:role] || determine_role(mention_data[:type]),
            text: mention_data[:name]
          }
        end

        # Find the source lines where this fact appears in the response
        line_info = find_source_lines(fact_data[:text], response_lines, mentions)

        # Create the fact with source line information
        fact = @fact_service.create(
          fact_data[:text],
          valid_at: fact_data[:valid_at] || Date.today,
          invalid_at: fact_data[:invalid_at],
          extraction_method: :llm,
          status: :synthesized,  # Mark as synthesized from LLM
          confidence: (fact_data[:confidence] || 0.7) * 0.9,  # Slight discount for synthesized facts
          mentions: mentions.uniq { |m| m[:entity_id] },
          metadata: {
            source_type: "rag_synthesis",
            extraction_timestamp: Time.now.iso8601,
            line_start: line_info[:line_start],
            line_end: line_info[:line_end]
          }
        )

        fact.add_source(source: source, type: :primary, confidence: 0.9)
        extracted_facts << fact

      rescue StandardError => e
        debug_me { [:fact_data, :e] } if @verbose
        # Continue with other facts
      end
    rescue StandardError => e
      debug_me { [:e] }
      puts "Error during fact extraction: #{e.message}"
    end

    extracted_facts
  end

  # Find an existing fact that matches the given text (duplicate detection)
  def find_duplicate_fact(text)
    normalized_text = normalize_text(text)
    return nil if normalized_text.length < 10

    # Search for similar facts
    candidates = @fact_service.search(text, status: nil, limit: 10)

    candidates.find do |candidate|
      normalized_candidate = normalize_text(candidate.text)
      # Consider it a duplicate if normalized texts are very similar
      text_similarity(normalized_text, normalized_candidate) > 0.85
    end
  end

  def normalize_text(text)
    text.downcase
        .gsub(/[^a-z0-9\s]/, "")
        .gsub(/\s+/, " ")
        .strip
  end

  def text_similarity(text1, text2)
    return 1.0 if text1 == text2
    return 0.0 if text1.empty? || text2.empty?

    # Simple word overlap similarity
    words1 = text1.split.to_set
    words2 = text2.split.to_set
    intersection = words1 & words2
    union = words1 | words2

    union.empty? ? 0.0 : intersection.size.to_f / union.size
  end

  # Find the line numbers in the source text where a fact most likely originated
  def find_source_lines(text, source_lines, mentions)
    return { line_start: 1, line_end: source_lines.length } if source_lines.empty?

    # Extract key terms from the fact and entity mentions
    key_terms = extract_fact_key_terms(text, mentions)
    return { line_start: 1, line_end: source_lines.length } if key_terms.empty?

    # Score each line by how many key terms it contains
    line_scores = source_lines.each_with_index.map do |line, idx|
      line_lower = line.downcase
      score = key_terms.count { |term| line_lower.include?(term.downcase) }
      { line_number: idx + 1, score: score }
    end

    # Find lines with matches
    matching_lines = line_scores.select { |l| l[:score] > 0 }

    if matching_lines.empty?
      # No direct matches - return full document range
      { line_start: 1, line_end: source_lines.length }
    else
      # Return the range covering all matching lines, plus context
      first_match = matching_lines.first[:line_number]
      last_match = matching_lines.last[:line_number]

      # Add 1 line of context on each side
      line_start = [first_match - 1, 1].max
      line_end = [last_match + 1, source_lines.length].min

      { line_start: line_start, line_end: line_end }
    end
  end

  def extract_fact_key_terms(text, mentions)
    terms = []

    # Add entity names from mentions
    mentions.each do |mention|
      terms << mention[:text] if mention[:text]
    end

    # Extract significant words from the fact text
    stop_words = %w[a an the is was were are been being have has had do does did
                    will would could should may might must shall can to of in for
                    on with at by from as into through during before after]

    fact_words = text.downcase
                          .gsub(/[^a-z\s]/, " ")
                          .split
                          .reject { |w| w.length < 4 || stop_words.include?(w) }
                          .uniq

    terms.concat(fact_words)
    terms.compact.uniq.reject(&:empty?)
  end

  def determine_role(entity_type)
    case entity_type.to_s
    when "person" then :subject
    when "place" then :location
    when "organization" then :object
    when "event" then :temporal
    else :subject
    end
  end

  def report_new_entries(extracted_facts)
    puts "\n" + "=" * 60
    puts "NEW DATABASE ENTRIES"
    puts "=" * 60

    # Calculate deltas
    facts_added = @stats_after[:facts] - @stats_before[:facts]
    entities_added = @stats_after[:entities] - @stats_before[:entities]
    sources_added = @stats_after[:sources] - @stats_before[:sources]
    duplicates_found = @duplicate_facts&.size || 0

    puts "\nSummary:"
    puts "  Source records added:  #{sources_added}"
    puts "  Facts extracted:       #{facts_added}"
    puts "  Duplicates skipped:    #{duplicates_found}" if duplicates_found > 0
    puts "  Entities discovered:   #{entities_added}"

    if extracted_facts.any?
      puts "\nExtracted Facts:"
      extracted_facts.each do |fact|
        puts "\n  [ID: #{fact.id}] #{fact.text[0..90]}#{'...' if fact.text.length > 90}"

        entities = fact.entity_mentions.map { |m| m.entity.name }
        puts "     Entities: #{entities.join(', ')}" if entities.any?
        puts "     Confidence: #{(fact.confidence * 100).round(1)}%"
        puts "     Status: #{fact.status}"
      end
    else
      puts "\n  No new facts were extracted from the LLM response."
    end

    # Show duplicates that were skipped
    if @duplicate_facts&.any?
      puts "\nDuplicate Facts (skipped):"
      @duplicate_facts.each do |dup|
        existing = dup[:existing_fact]
        puts "\n  [DUP of ID: #{existing.id}] #{dup[:extracted_text][0..80]}..."
        puts "     Existing: #{existing.text[0..80]}..."
      end
    end

    # Show any new entities
    if entities_added > 0
      puts "\nNew Entities Discovered:"
      new_entities = FactDb::Models::Entity
                       .order(created_at: :desc)
                       .limit(entities_added)

      new_entities.each do |entity|
        puts "  - #{entity.name} (#{entity.type})"
      end
    end

    puts
  end

  def display_context(facts)
    puts "\n--- Retrieved Context ---"
    @scored_context.each_with_index do |scored_fact, idx|
      fact = scored_fact[:fact]
      score = scored_fact[:score]
      puts "  #{idx + 1}. [#{(score * 100).round(1)}%] #{fact.text[0..70]}..."
    end
    if @filtered_count > 0
      puts "  (#{@filtered_count} facts filtered out due to low relevance)"
    end
    puts
  end

  def display_enhanced_prompt(prompt)
    puts "\n" + "=" * 60
    puts "ENHANCED PROMPT"
    puts "=" * 60
    puts prompt
    puts "=" * 60
  end

  def display_llm_response(response)
    puts "\n" + "=" * 60
    puts "LLM RESPONSE"
    puts "=" * 60
    puts response
    puts "=" * 60
  end

  def with_spinner(message)
    spinner_chars = %w[... .. . .. ...]
    spinning = true
    result = nil

    spinner_thread = Thread.new do
      i = 0
      while spinning
        print "\r  #{spinner_chars[i % spinner_chars.length]} #{message}    "
        $stdout.flush
        sleep 0.3
        i += 1
      end
    end

    begin
      result = yield
    ensure
      spinning = false
      spinner_thread.join
      print "\r#{' ' * (message.length + 15)}\r"
      $stdout.flush
    end

    result
  end

  def log_header(prompt)
    puts "=" * 60
    puts "RAG Feedback Loop Demo"
    puts "=" * 60
    puts "Prompt: #{prompt}"
    puts "Mode: #{mode_description}"
    puts "Context limit: #{@limit} facts"
    puts "Min relevance: #{(@min_relevance * 100).round(1)}%" if @min_relevance > 0
    puts
  end

  def mode_description
    return "Context Only" if @context_only
    return "Dry Run" if @dry_run

    "Full Pipeline"
  end

  def log_step(label, value)
    return unless @verbose || !value.is_a?(Array)

    if value.is_a?(Array)
      puts "\n--- #{label} ---"
      if value.empty?
        puts "  (none)"
      else
        value.each { |v| puts "  - #{v}" }
      end
    else
      puts "  [#{label}] #{value}"
    end
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  options = { verbose: false, dry_run: false, context_only: false, limit: 15, min_relevance: 0.0, format: :text }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options] \"prompt\""

    opts.on("-v", "--verbose", "Show detailed processing steps") do
      options[:verbose] = true
    end

    opts.on("-d", "--dry-run", "Show enhanced prompt without calling LLM") do
      options[:dry_run] = true
    end

    opts.on("-c", "--context-only", "Show retrieved context without LLM processing") do
      options[:context_only] = true
    end

    opts.on("-l", "--limit N", Integer, "Maximum facts for context (default: 15)") do |n|
      options[:limit] = n
    end

    opts.on("-m", "--min-relevance PERCENT", Float,
            "Minimum relevance score 0-100 to include fact (default: 0)") do |p|
      options[:min_relevance] = p / 100.0
    end

    opts.on("-f", "--format FORMAT", RagFeedbackLoop::CONTEXT_FORMATS,
            "Context format: text, json (default: text)") do |f|
      options[:format] = f
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      puts <<~EXAMPLES

        Examples:
          #{$PROGRAM_NAME} "What are the key events in Acts chapter 5?"
          #{$PROGRAM_NAME} --verbose "Tell me about Ananias and Sapphira"
          #{$PROGRAM_NAME} --dry-run "Summarize Peter's role in Acts"
          #{$PROGRAM_NAME} --context-only "Who was Stephen?"
          #{$PROGRAM_NAME} --min-relevance 15 "Tell me about the Comanche"
          #{$PROGRAM_NAME} --format json "What happened to the apostles?"

        Workflow:
          1. Retrieves relevant facts from the database based on your prompt
          2. Builds an enhanced prompt with the retrieved context
          3. Sends the enhanced prompt to the configured LLM
          4. Ingests the LLM response as new content in the database
          5. Extracts atomic facts from the response using LLM extraction
          6. Reports on all new facts and entities added to the database

        Knowledge Compounding:
          Each query potentially adds new synthesized knowledge to the database.
          Subsequent queries can then leverage this expanded knowledge base,
          creating a compounding effect where the system becomes more knowledgeable
          over time.

        Prerequisites:
          - Run ingest_demo.rb first to populate the database with initial facts
          - Configure LLM provider (ANTHROPIC_API_KEY, OPENAI_API_KEY, etc.)

        Environment:
          FACT_DB_LLM_PROVIDER  # LLM provider (anthropic, openai, gemini, ollama)
          ANTHROPIC_API_KEY     # API key for Anthropic (default provider)
          OPENAI_API_KEY        # API key for OpenAI
          DATABASE_URL          # PostgreSQL connection URL
      EXAMPLES
      exit 0
    end
  end

  parser.parse!

  if ARGV.empty?
    puts "Error: Please provide a prompt"
    puts "Usage: #{$PROGRAM_NAME} [options] \"your prompt here\""
    puts "Run '#{$PROGRAM_NAME} --help' for more information"
    exit 1
  end

  prompt = ARGV.join(" ")
  RagFeedbackLoop.new(**options).run(prompt)
end
