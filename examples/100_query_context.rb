#!/usr/bin/env ruby
# frozen_string_literal: true

# Query Context Generator for FactDb
#
# Takes a natural language query and generates context from the facts database
# suitable for LLM consumption.
#
# Usage:
#   ruby query_context.rb "Who is Sapphira's husband?"
#   ruby query_context.rb "What happened to Ananias?"
#   ruby query_context.rb --format triples "Tell me about Peter"
#   ruby query_context.rb --format json "Who are the apostles?"
#   ruby query_context.rb --verbose "Where was Stephen martyred?"
#
# Options:
#   --format FORMAT    Output format: text (default), json, triples, cypher
#   --verbose          Show detailed processing steps
#   --limit N          Maximum number of facts to return (default: 20)

require_relative "utilities"
require "optparse"

# Note: CLI tool - uses cli_setup! which does NOT reset database

class QueryContextGenerator
  FORMATS = %i[text json triples cypher raw].freeze

  def initialize(options = {})
    @format = options[:format] || :text
    @verbose = options[:verbose] || false
    @limit = options[:limit] || 20
    @rank = options[:rank] != false  # Default to true
    setup_factdb
    @query_embedding = nil  # Cache for query embedding
    load_ranking_weights
  end

  def load_ranking_weights
    ranking = FactDb.config.ranking

    # Load weights from config with fallback defaults
    @weights = {
      ts_rank: ranking&.ts_rank_weight || 0.25,
      vector_similarity: ranking&.vector_similarity_weight || 0.25,
      entity_mentions: ranking&.entity_mention_weight || 0.15,
      direct_answer: ranking&.direct_answer_weight || 0.15,
      term_overlap: ranking&.term_overlap_weight || 0.10,
      relationship_match: ranking&.relationship_match_weight || 0.05,
      confidence: ranking&.confidence_weight || 0.05
    }

    log_step("Ranking weights loaded", @weights.map { |k, v| "#{k}: #{v}" }) if @verbose
  end

  def run(query)
    log_header(query)

    # Step 1: Extract potential entity names from the query
    candidates = extract_entity_candidates(query)
    log_step("Entity candidates", candidates)

    # Step 2: Resolve entities from candidates
    resolved_entities = resolve_entities(candidates)
    log_step("Resolved entities", resolved_entities.map { |e| "#{e.canonical_name} (#{e.entity_type})" })

    # Step 3: Gather facts from multiple strategies
    all_facts = gather_facts(query, resolved_entities)
    log_step("Facts gathered", "#{all_facts.size} facts")

    # Step 4: Rank facts by relevance to the query
    @ranked_results = nil
    if @rank
      @ranked_results = rank_facts(query, all_facts, resolved_entities)
      log_step("Top ranked facts", @ranked_results.first(5).map { |f| "#{f[:score].round(2)}: #{f[:fact].fact_text[0..60]}..." })
      all_facts = @ranked_results.map { |f| f[:fact] }

      # Show signal breakdown if verbose
      if @verbose && @ranked_results.any?
        show_signal_breakdown(@ranked_results.first(3))
      end
    end

    # Step 5: Build and output context
    output_context(query, resolved_entities, all_facts)
  end

  def show_signal_breakdown(ranked_facts)
    puts "\n--- Signal Breakdown (Top #{ranked_facts.size}) ---"
    puts "    Configured weights: #{@weights.map { |k, v| "#{k}=#{v}" }.join(', ')}"

    ranked_facts.each_with_index do |result, idx|
      fact = result[:fact]
      signals = result[:signals]

      puts "\n#{idx + 1}. \"#{fact.fact_text[0..70]}...\""
      puts "   Total Score: #{result[:score].round(3)}"
      puts "   Signals:"

      signals.each do |name, value|
        max_weight = @weights[name] || 0.25
        fill_ratio = max_weight > 0 ? (value / max_weight) : 0
        bar_length = (fill_ratio * 10).round
        bar = "#" * bar_length + "." * (10 - bar_length)
        puts "     #{name.to_s.ljust(18)} #{value.round(3).to_s.ljust(6)} / #{max_weight.to_s.ljust(4)} |#{bar}|"
      end
    end
    puts
  end

  private

  def setup_factdb
    DemoUtilities.ensure_demo_environment!
    DemoUtilities.require_fact_db!

    FactDb.configure do |config|
      config.logger = Logger.new("/dev/null")
    end

    FactDb::Database.establish_connection!

    @facts = FactDb.new
    @entity_service = @facts.entity_service
    @fact_service = @facts.fact_service
  end

  def extract_entity_candidates(query)
    candidates = []

    # Extract capitalized words/phrases (potential proper nouns)
    # Match sequences of capitalized words
    query.scan(/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b/).each do |match|
      candidates << match unless stop_words.include?(match.downcase)
    end

    # Extract words in possessive form (e.g., "Sapphira's" -> "Sapphira")
    query.scan(/\b([A-Z][a-z]+)'s\b/).flatten.each do |match|
      candidates << match
    end

    # Extract quoted strings
    query.scan(/"([^"]+)"/).flatten.each do |match|
      candidates << match
    end

    # Also try key nouns from the query (lowercase entities might exist)
    extract_key_nouns(query).each do |noun|
      candidates << noun
    end

    candidates.uniq
  end

  def extract_key_nouns(query)
    nouns = []

    # Common question patterns - extract the object
    patterns = [
      /who (?:is|was|were) (.+?)(?:\?|$)/i,
      /what (?:is|was|were|happened to) (.+?)(?:\?|$)/i,
      /where (?:is|was|did) (.+?)(?:\?|$)/i,
      /tell me about (.+?)(?:\?|$)/i,
      /(?:husband|wife|spouse) of (.+?)(?:\?|$)/i,
      /(.+?)'s (?:husband|wife|father|mother|son|daughter)/i
    ]

    patterns.each do |pattern|
      if (match = query.match(pattern))
        # Clean up the captured group
        noun = match[1].strip.gsub(/[?.!]$/, "")
        nouns << noun unless noun.empty?
      end
    end

    nouns.uniq
  end

  def stop_words
    %w[who what where when why how is was were are the a an and or but]
  end

  def resolve_entities(candidates)
    entities = []

    candidates.each do |name|
      # Try exact resolution first
      resolved = @entity_service.resolve(name)
      if resolved
        entities << resolved.entity
        next
      end

      # Try search as fallback
      search_results = @entity_service.search(name, limit: 3)
      search_results.each do |entity|
        entities << entity
      end
    end

    entities.uniq(&:id)
  end

  def gather_facts(query, entities)
    facts = []

    # Strategy 1: Get facts mentioning resolved entities
    entities.each do |entity|
      entity_facts = @fact_service.current_facts(entity: entity.id, limit: @limit)
      facts.concat(entity_facts.to_a)
    end

    # Strategy 2: Full-text search on the query
    search_facts = @fact_service.search(query, limit: @limit)
    facts.concat(search_facts.to_a)

    # Strategy 3: Search for key terms from the query
    extract_search_terms(query).each do |term|
      term_facts = @fact_service.search(term, limit: 5)
      facts.concat(term_facts.to_a)
    end

    # Strategy 4: Semantic search if available
    begin
      semantic_facts = @fact_service.semantic_search(query, limit: @limit)
      facts.concat(semantic_facts.to_a) if semantic_facts.any?
    rescue StandardError
      # Semantic search not available (no embeddings)
    end

    # Deduplicate and limit
    facts.uniq(&:id).first(@limit)
  end

  # Rank facts by relevance to the query
  # Returns array of { fact:, score:, signals: } sorted by score descending
  def rank_facts(query, facts, resolved_entities)
    return [] if facts.empty?

    query_lower = query.downcase
    query_terms = extract_query_terms(query)
    entity_names = resolved_entities.flat_map { |e| [e.canonical_name.downcase] + e.all_aliases.map(&:downcase) }

    # Pre-compute expensive scores for all facts at once
    fact_ids = facts.map(&:id)
    ts_rank_scores = compute_ts_rank_scores(query, fact_ids)
    vector_scores = compute_vector_similarity_scores(query, fact_ids)

    scored_facts = facts.map do |fact|
      signals = {}
      fact_text_lower = fact.fact_text.downcase

      # Signal 1: PostgreSQL ts_rank score
      # Full-text search relevance from PostgreSQL
      ts_score = ts_rank_scores[fact.id] || 0.0
      signals[:ts_rank] = [ts_score * @weights[:ts_rank], @weights[:ts_rank]].min

      # Signal 2: Vector similarity score
      # Semantic similarity via pgvector embeddings
      vec_score = vector_scores[fact.id] || 0.0
      signals[:vector_similarity] = vec_score * @weights[:vector_similarity]

      # Signal 3: Entity mention score
      # Facts mentioning query entities rank higher
      entity_mention_score = 0.0
      mention_increment = @weights[:entity_mentions] / 2.0  # Allow up to 2 entity mentions
      entity_names.each do |name|
        entity_mention_score += mention_increment if fact_text_lower.include?(name)
      end
      signals[:entity_mentions] = [entity_mention_score, @weights[:entity_mentions]].min

      # Signal 4: Query term overlap
      # How many query terms appear in the fact
      term_matches = query_terms.count { |term| fact_text_lower.include?(term.downcase) }
      term_score = query_terms.empty? ? 0 : (term_matches.to_f / query_terms.size) * @weights[:term_overlap]
      signals[:term_overlap] = term_score

      # Signal 5: Relationship term bonus
      # Bonus for facts containing relationship words from the query
      relationship_terms = extract_relationship_terms(query)
      rel_matches = relationship_terms.count { |term| fact_text_lower.include?(term.downcase) }
      signals[:relationship_match] = rel_matches > 0 ? @weights[:relationship_match] : 0.0

      # Signal 6: Direct answer bonus
      # Bonus if fact structure matches query intent (uses relative scoring)
      direct_score = score_direct_answer(query, fact)
      signals[:direct_answer] = direct_score * @weights[:direct_answer] / 0.25  # Normalize from original 0.25 max

      # Signal 7: Fact confidence
      # Use the fact's stored confidence score
      signals[:confidence] = (fact.confidence || 0.5) * @weights[:confidence]

      # Calculate total score
      total_score = signals.values.sum

      { fact: fact, score: total_score, signals: signals }
    end

    scored_facts.sort_by { |f| -f[:score] }
  end

  # Compute PostgreSQL ts_rank scores for full-text search relevance
  # Returns hash of { fact_id => normalized_score (0-1) }
  def compute_ts_rank_scores(query, fact_ids)
    return {} if fact_ids.empty? || query.strip.empty?

    # Use ts_rank_cd (cover density) for better phrase matching
    sql = <<~SQL
      SELECT id,
             ts_rank_cd(to_tsvector('english', fact_text),
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
    if max_score > 0
      scores.transform_values { |s| s / max_score }
    else
      scores
    end
  rescue StandardError => e
    log_step("ts_rank error", e.message) if @verbose
    {}
  end

  # Compute vector similarity scores using pgvector
  # Returns hash of { fact_id => similarity_score (0-1) }
  def compute_vector_similarity_scores(query, fact_ids)
    return {} if fact_ids.empty?

    # Get query embedding (cached)
    query_embedding = get_query_embedding(query)
    return {} unless query_embedding

    # Use pgvector's cosine distance operator (<=>)
    # Convert distance to similarity: similarity = 1 - distance
    # Cosine distance ranges from 0 (identical) to 2 (opposite)
    sql = <<~SQL
      SELECT id,
             1 - (embedding <=> ?) as similarity
      FROM fact_db_facts
      WHERE id IN (?)
        AND embedding IS NOT NULL
    SQL

    # Format embedding as PostgreSQL vector string
    embedding_str = "[#{query_embedding.join(',')}]"

    results = ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql([sql, embedding_str, fact_ids])
    )

    scores = {}
    results.each do |row|
      # Clamp to 0-1 range (cosine similarity can be negative for opposite vectors)
      similarity = [[row["similarity"].to_f, 0.0].max, 1.0].min
      scores[row["id"]] = similarity
    end

    scores
  rescue StandardError => e
    log_step("vector similarity error", e.message) if @verbose
    {}
  end

  # Get or generate embedding for the query
  def get_query_embedding(query)
    return @query_embedding if @query_embedding

    embedding_generator = FactDb.config.embedding_generator
    return nil unless embedding_generator

    @query_embedding = embedding_generator.call(query)
    log_step("Query embedding", "Generated #{@query_embedding&.size || 0} dimensions") if @verbose
    @query_embedding
  rescue StandardError => e
    log_step("embedding error", e.message) if @verbose
    nil
  end

  def extract_query_terms(query)
    # Extract meaningful terms from query, excluding stop words
    stop_words = %w[who what where when why how is was were are the a an and or but
                    to of in for on with at by from as tell me about]
    query.downcase
         .gsub(/[^a-z\s']/, " ")
         .split
         .reject { |w| w.length < 2 || stop_words.include?(w) }
         .uniq
  end

  def extract_relationship_terms(query)
    # Extract relationship-indicating terms from query
    relationship_words = %w[husband wife spouse married father mother son daughter
                            brother sister parent child born died killed
                            works worked employed job role position title
                            lives lived location city country
                            member belongs part joined left]

    query_lower = query.downcase
    relationship_words.select { |word| query_lower.include?(word) }
  end

  def score_direct_answer(query, fact)
    query_lower = query.downcase
    fact_lower = fact.fact_text.downcase

    # Pattern: "Who is X's husband/wife?" -> look for spouse relationships
    # Recognize both the queried term AND its inverse (wife/husband)
    if query_lower.include?("husband") || query_lower.include?("wife")
      # Highest score for facts that define the relationship
      if fact_lower.match?(/('s|his|her) (husband|wife)\b/) ||
         fact_lower.match?(/\b(husband|wife) (of|named|was|is)\b/) ||
         fact_lower.match?(/\bhad a (husband|wife)\b/) ||
         fact_lower.match?(/\bmarried to\b/)
        return 0.25
      end
      # Good score for facts mentioning spouse terms
      return 0.2 if fact_lower.include?("husband") || fact_lower.include?("wife") || fact_lower.include?("married")
    end

    # Pattern: "What happened to X?" -> look for action verbs about X
    if query_lower.match?(/what happened/)
      return 0.15 if fact_lower.match?(/died|killed|fell|buried|arrested|healed|spoke/)
    end

    # Pattern: "Where was X?" -> look for location indicators
    if query_lower.match?(/where (was|is|did)/)
      return 0.15 if fact_lower.match?(/in |at |to |from |temple|jerusalem|prison|house/)
    end

    # Pattern: "Who are the X?" -> look for group membership
    if query_lower.match?(/who are/)
      return 0.1 if fact_lower.match?(/apostle|disciple|believer|member/)
    end

    0.0
  end

  def extract_search_terms(query)
    terms = []

    # Relationship terms to search for
    relationship_words = %w[husband wife spouse father mother son daughter
                            brother sister married killed died born
                            apostle disciple prophet leader]

    relationship_words.each do |word|
      terms << word if query.downcase.include?(word)
    end

    # Add entity names as search terms
    query.scan(/\b[A-Z][a-z]+\b/).each do |word|
      terms << word unless stop_words.include?(word.downcase)
    end

    terms.uniq
  end

  def output_context(query, entities, facts)
    if facts.empty? && entities.empty?
      puts "No relevant context found for: #{query}"
      puts "\nTry:"
      puts "  - Check if data has been ingested (run ingest_demo.rb first)"
      puts "  - Use different search terms"
      puts "  - Check available entities with: ruby introspection.rb"
      return
    end

    # Build QueryResult for transformer
    result = FactDb::QueryResult.new(query: query)
    result.add_facts(facts)
    result.resolve_entities(@entity_service)

    case @format
    when :text
      output_text_context(query, result)
    when :json
      output_json_context(result)
    when :triples
      output_triples_context(result)
    when :cypher
      output_cypher_context(result)
    when :raw
      output_raw_context(result)
    end
  end

  def output_text_context(query, result)
    puts <<~HEADER
      ================================================================================
      CONTEXT FOR QUERY: #{query}
      ================================================================================

    HEADER

    transformer = FactDb::Transformers::TextTransformer.new
    puts transformer.transform(result)

    puts <<~FOOTER

      --------------------------------------------------------------------------------
      Retrieved #{result.fact_count} facts about #{result.entity_count} entities
      ================================================================================
    FOOTER
  end

  def output_json_context(result)
    require "json"
    puts JSON.pretty_generate(result.to_h)
  end

  def output_triples_context(result)
    transformer = FactDb::Transformers::TripleTransformer.new
    triples = transformer.transform(result)

    puts "# Triples for query: #{result.query}"
    puts "# Format: [subject, predicate, object]"
    puts

    triples.each do |triple|
      puts triple.inspect
    end

    puts
    puts "# Total: #{triples.size} triples"
  end

  def output_cypher_context(result)
    transformer = FactDb::Transformers::CypherTransformer.new
    cypher = transformer.transform(result)

    puts "// Cypher statements for query: #{result.query}"
    puts cypher
  end

  def output_raw_context(result)
    transformer = FactDb::Transformers::RawTransformer.new
    raw = transformer.transform(result)

    require "amazing_print"
    ap raw
  end

  def log_header(query)
    return unless @verbose

    puts "=" * 70
    puts "Query Context Generator"
    puts "=" * 70
    puts "Query: #{query}"
    puts "Format: #{@format}"
    puts "Limit: #{@limit}"
    puts
  end

  def log_step(label, value)
    return unless @verbose

    puts "--- #{label} ---"
    if value.is_a?(Array)
      if value.empty?
        puts "  (none)"
      else
        value.each { |v| puts "  - #{v}" }
      end
    else
      puts "  #{value}"
    end
    puts
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  options = { format: :text, verbose: false, limit: 20, rank: true }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options] \"query\""

    opts.on("-f", "--format FORMAT", QueryContextGenerator::FORMATS,
            "Output format (#{QueryContextGenerator::FORMATS.join(', ')})") do |f|
      options[:format] = f
    end

    opts.on("-v", "--verbose", "Show detailed processing steps") do
      options[:verbose] = true
    end

    opts.on("-l", "--limit N", Integer, "Maximum facts to return (default: 20)") do |n|
      options[:limit] = n
    end

    opts.on("--no-rank", "Disable relevance ranking") do
      options[:rank] = false
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      puts <<~EXAMPLES

        Examples:
          #{$PROGRAM_NAME} "Who is Sapphira's husband?"
          #{$PROGRAM_NAME} "What happened to Ananias?"
          #{$PROGRAM_NAME} --format triples "Tell me about Peter"
          #{$PROGRAM_NAME} --format json "Who are the apostles?"
          #{$PROGRAM_NAME} --verbose "Where was Stephen martyred?"
          #{$PROGRAM_NAME} --no-rank "Tell me about the apostles"

        Relevance Ranking:
          Facts are ranked using configurable signal weights (defaults shown):
          - ts_rank_weight: 0.25            PostgreSQL full-text search relevance
          - vector_similarity_weight: 0.25  Semantic similarity via pgvector
          - entity_mention_weight: 0.15     Facts mentioning query entities
          - direct_answer_weight: 0.15      Pattern match for query intent
          - term_overlap_weight: 0.10       Query word matches
          - relationship_match_weight: 0.05 Relationship words (husband, etc.)
          - confidence_weight: 0.05         Fact's stored confidence score

          Configure weights in FactDb:
            FactDb.configure do |config|
              config.ranking.ts_rank_weight = 0.30
              config.ranking.vector_similarity_weight = 0.20
              # ... etc
            end

          Or via environment variables:
            FDB_RANKING__TS_RANK_WEIGHT=0.30

          Note: vector_similarity requires embedding_generator to be configured.

        Prerequisites:
          Run ingest_demo.rb to populate the database with facts first:
            ruby ingest_demo.rb acts_esv/

        Environment:
          DATABASE_URL  # PostgreSQL connection (default: postgres://$USER@localhost/fact_db_demo)
      EXAMPLES
      exit 0
    end
  end

  parser.parse!

  if ARGV.empty?
    puts "Error: Please provide a query"
    puts parser
    exit 1
  end

  query = ARGV.join(" ")
  QueryContextGenerator.new(options).run(query)
end
