# frozen_string_literal: true

require "active_record"
require "digest"

require_relative "fact_db/version"
require_relative "fact_db/errors"
require_relative "fact_db/config"
require_relative "fact_db/database"

# Models
require_relative "fact_db/models/source"
require_relative "fact_db/models/entity"
require_relative "fact_db/models/entity_alias"
require_relative "fact_db/models/fact"
require_relative "fact_db/models/entity_mention"
require_relative "fact_db/models/fact_source"

# Temporal queries
require_relative "fact_db/temporal/query"
require_relative "fact_db/temporal/timeline"
require_relative "fact_db/temporal/query_builder"

# Resolution
require_relative "fact_db/resolution/entity_resolver"
require_relative "fact_db/resolution/fact_resolver"

# Validation
require_relative "fact_db/validation/alias_filter"

# Extractors
require_relative "fact_db/extractors/base"
require_relative "fact_db/extractors/manual_extractor"
require_relative "fact_db/extractors/llm_extractor"
require_relative "fact_db/extractors/rule_based_extractor"

# LLM Integration
require_relative "fact_db/llm/adapter"

# Pipeline (concurrent processing)
require_relative "fact_db/pipeline/extraction_pipeline"
require_relative "fact_db/pipeline/resolution_pipeline"

# Services
require_relative "fact_db/services/source_service"
require_relative "fact_db/services/entity_service"
require_relative "fact_db/services/fact_service"

# Transformers (output formatting)
require_relative "fact_db/transformers/base"
require_relative "fact_db/transformers/raw_transformer"
require_relative "fact_db/transformers/json_transformer"
require_relative "fact_db/transformers/triple_transformer"
require_relative "fact_db/transformers/cypher_transformer"
require_relative "fact_db/transformers/text_transformer"

# Query Result
require_relative "fact_db/query_result"

module FactDb
  class Facts
    # Available output formats for LLM consumption
    FORMATS = %i[raw json triples cypher text].freeze

    # Available retrieval strategies
    STRATEGIES = %i[auto semantic fulltext graph temporal hybrid].freeze

    attr_reader :config, :source_service, :entity_service, :fact_service,
                :extraction_pipeline, :resolution_pipeline

    def initialize(config: nil)
      @config = config || FactDb.config
      Database.establish_connection!(@config)

      @source_service = Services::SourceService.new(@config)
      @entity_service = Services::EntityService.new(@config)
      @fact_service = Services::FactService.new(@config)
      @extraction_pipeline = Pipeline::ExtractionPipeline.new(@config)
      @resolution_pipeline = Pipeline::ResolutionPipeline.new(@config)
      @transformers = build_transformers
    end

    # Ingest raw content
    def ingest(content, type:, captured_at: Time.current, metadata: {}, title: nil, source_uri: nil)
      @source_service.create(
        content,
        type: type,
        captured_at: captured_at,
        metadata: metadata,
        title: title,
        source_uri: source_uri
      )
    end

    # Extract facts from source
    def extract_facts(source_id, extractor: @config.default_extractor)
      @fact_service.extract_from_source(source_id, extractor: extractor)
    end

    # Query facts with temporal and entity filtering
    #
    # @param topic [String, nil] Topic to search for
    # @param at [Date, Time, String, nil] Point in time for temporal query
    # @param entity [Integer, nil] Entity ID to filter by
    # @param status [Symbol] Fact status (:canonical, :superseded, :synthesized, :all)
    # @param format [Symbol] Output format (:json, :triples, :cypher, :text, :prolog)
    # @return [Array, String, Hash] Results in requested format
    def query_facts(topic: nil, at: nil, entity: nil, status: :canonical, format: :json)
      results = @fact_service.query(topic: topic, at: at, entity: entity, status: status)
      transform_results(results, topic: topic, format: format)
    end

    # Resolve a name to an entity
    def resolve_entity(name, type: nil)
      @entity_service.resolve(name, type: type)
    end

    # Build a timeline for an entity
    def timeline_for(entity_id, from: nil, to: nil)
      @fact_service.timeline(entity_id: entity_id, from: from, to: to)
    end

    # Get currently valid facts about an entity
    #
    # @param entity_id [Integer] Entity ID
    # @param format [Symbol] Output format
    # @return [Array, String, Hash] Results in requested format
    def current_facts_for(entity_id, format: :json)
      results = @fact_service.current_facts(entity: entity_id)
      transform_results(results, topic: "entity_#{entity_id}", format: format)
    end

    # Get facts valid at a specific point in time
    #
    # @param at [Date, Time, String] Point in time
    # @param entity [Integer, nil] Entity ID to filter by
    # @param topic [String, nil] Topic to search for
    # @param format [Symbol] Output format
    # @return [Array, String, Hash] Results in requested format
    def facts_at(at, entity: nil, topic: nil, format: :json)
      results = @fact_service.facts_at(at, entity: entity, topic: topic)
      transform_results(results, topic: topic || "facts_at_#{at}", format: format)
    end

    # Temporal query builder - query at a specific point in time
    #
    # @param date [Date, Time, String] Point in time
    # @return [Temporal::QueryBuilder] Scoped query builder
    #
    # @example
    #   facts.at("2024-01-15").query("Paula's role", format: :cypher)
    #   facts.at("2024-01-15").facts_for(entity_id)
    #   facts.at("2024-01-15").compare_to("2024-06-15")
    def at(date)
      Temporal::QueryBuilder.new(self, parse_date(date))
    end

    # Compare what changed between two dates
    #
    # @param topic [String, nil] Topic to compare (nil for all facts)
    # @param from [Date, Time, String] Start date
    # @param to [Date, Time, String] End date
    # @return [Hash] Differences with :added, :removed, :unchanged keys
    def diff(topic = nil, from:, to:)
      from_date = parse_date(from)
      to_date = parse_date(to)

      from_results = @fact_service.query(topic: topic, at: from_date, status: :canonical)
      to_results = @fact_service.query(topic: topic, at: to_date, status: :canonical)

      from_set = facts_to_comparable(from_results)
      to_set = facts_to_comparable(to_results)

      {
        topic: topic,
        from: from_date,
        to: to_date,
        added: to_results.select { |f| !from_set.include?(comparable_key(f)) },
        removed: from_results.select { |f| !to_set.include?(comparable_key(f)) },
        unchanged: from_results.select { |f| to_set.include?(comparable_key(f)) }
      }
    end

    # Introspect the schema - what does the layer know about?
    #
    # @param topic [String, nil] Optional topic to introspect specifically
    # @return [Hash] Schema information or topic-specific coverage
    def introspect(topic = nil)
      topic ? introspect_topic(topic) : introspect_schema
    end

    # Suggest queries based on what's stored for a topic
    #
    # @param topic [String] Topic to get suggestions for
    # @return [Array<String>] Suggested queries
    def suggest_queries(topic)
      resolved = resolve_entity(topic)
      return [] unless resolved

      entity = resolved.respond_to?(:entity) ? resolved.entity : resolved
      suggestions = []

      entity_type = entity.respond_to?(:type) ? entity.type : nil
      suggestions << "current status" if entity_type == "person"

      # Check relationships
      relationships = @entity_service.relationship_types_for(entity.id)
      suggestions << "employment history" if relationships.include?(:works_at) || relationships.include?(:object)
      suggestions << "team members" if relationships.include?(:works_with)
      suggestions << "reporting chain" if relationships.include?(:reports_to)

      # Check fact coverage
      fact_stats = @fact_service.fact_stats(entity.id)
      suggestions << "timeline" if fact_stats[:canonical]&.positive?
      suggestions << "historical changes" if fact_stats[:superseded]&.positive?

      suggestions
    end

    # Suggest retrieval strategies for a query
    #
    # @param query_text [String] The query
    # @return [Array<Hash>] Strategy options with descriptions
    def suggest_strategies(query_text)
      strategies = []

      # Check for temporal keywords
      if query_text.match?(/\b(yesterday|last\s+week|last\s+month|ago|since|before|after|between)\b/i)
        strategies << { strategy: :temporal, description: "Filter by date range" }
      end

      # Check for semantic intent
      if query_text.match?(/\b(about|related|similar|like)\b/i)
        strategies << { strategy: :semantic, description: "Search by semantic similarity" }
      end

      # Check for entity focus
      if query_text.match?(/\b(who|what|where)\b/i)
        strategies << { strategy: :graph, description: "Traverse from entity node" }
      end

      # Default: hybrid
      strategies << { strategy: :hybrid, description: "Combine multiple strategies" }

      strategies
    end

    # Batch extract facts from multiple sources
    #
    # @param source_ids [Array<Integer>] Source IDs to process
    # @param extractor [Symbol] Extractor type (:manual, :llm, :rule_based)
    # @param parallel [Boolean] Whether to use parallel processing
    # @return [Array<Hash>] Results with extracted facts per source
    def batch_extract(source_ids, extractor: @config.default_extractor, parallel: true)
      sources = Models::Source.where(id: source_ids).to_a
      if parallel
        @extraction_pipeline.process_parallel(sources, extractor: extractor)
      else
        @extraction_pipeline.process(sources, extractor: extractor)
      end
    end

    # Batch resolve entity names
    #
    # @param names [Array<String>] Entity names to resolve
    # @param type [Symbol, nil] Entity type filter
    # @return [Array<Hash>] Resolution results
    def batch_resolve_entities(names, type: nil)
      @resolution_pipeline.resolve_entities(names, type: type)
    end

    # Detect fact conflicts for multiple entities
    #
    # @param entity_ids [Array<Integer>] Entity IDs to check
    # @return [Array<Hash>] Conflict detection results
    def detect_fact_conflicts(entity_ids)
      @resolution_pipeline.detect_conflicts(entity_ids)
    end

    private

    def build_transformers
      {
        raw: Transformers::RawTransformer.new,
        json: Transformers::JsonTransformer.new,
        triples: Transformers::TripleTransformer.new,
        cypher: Transformers::CypherTransformer.new,
        text: Transformers::TextTransformer.new
      }
    end

    def transform_results(results, topic:, format:)
      validate_format!(format)

      query_result = QueryResult.new(query: topic || "query")
      query_result.add_facts(results)
      query_result.resolve_entities(@entity_service)

      # Return QueryResult directly for :json format to support fluent API methods
      # like each_fact, fact_count, etc. Use query_result.to_h for Hash output.
      return query_result if format == :json

      @transformers[format].transform(query_result)
    end

    def validate_format!(format)
      return if FORMATS.include?(format)

      raise ArgumentError, "Unknown format: #{format}. Available: #{FORMATS.join(', ')}"
    end

    def parse_date(date)
      return nil if date.nil?
      return date if date.is_a?(Date) || date.is_a?(Time)

      Date.parse(date.to_s)
    rescue ArgumentError
      nil
    end

    def introspect_schema
      {
        capabilities: collect_capabilities,
        entity_types: Models::Entity.distinct.pluck(:type).compact,
        fact_statuses: %w[canonical superseded corroborated synthesized],
        extraction_methods: %w[manual llm rule_based],
        output_formats: FORMATS,
        retrieval_strategies: STRATEGIES,
        statistics: collect_statistics
      }
    end

    def introspect_topic(topic)
      resolved = resolve_entity(topic)
      return nil unless resolved

      entity = resolved.respond_to?(:entity) ? resolved.entity : resolved

      {
        entity: entity_info(entity),
        coverage: {
          facts: @fact_service.fact_stats(entity.id),
          timespan: @entity_service.timespan_for(entity.id)
        },
        relationships: @entity_service.relationship_types_for(entity.id),
        suggested_queries: suggest_queries(topic)
      }
    end

    def collect_capabilities
      capabilities = [:temporal_query, :entity_resolution, :introspection]

      capabilities << :semantic_search if @config.embedding_generator
      capabilities << :llm_extraction if @config.llm_client || @config.llm&.provider

      capabilities
    end

    def collect_statistics
      {
        facts: @fact_service.stats,
        entities: @entity_service.stats,
        sources: @source_service.stats
      }
    end

    def entity_info(entity)
      {
        id: entity.id,
        canonical_name: entity.canonical_name,
        type: entity.type,
        resolution_status: entity.resolution_status,
        aliases: entity.aliases.map { |a| { alias_text: a.alias_text, alias_type: a.alias_type } }
      }
    end

    def facts_to_comparable(facts)
      facts.map { |f| comparable_key(f) }.to_set
    end

    def comparable_key(fact)
      text = fact.respond_to?(:fact_text) ? fact.fact_text : fact[:fact_text]
      "#{text}".downcase.strip
    end
  end

  class << self
    def new(**options)
      Facts.new(**options)
    end
  end
end
