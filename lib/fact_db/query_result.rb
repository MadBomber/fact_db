# frozen_string_literal: true

module FactDb
  # Holds the results of a query and provides a unified interface
  # for transformers to work with.
  #
  # @example Basic usage
  #   result = QueryResult.new(query: "Paula Chen")
  #   result.add_facts(facts)
  #   result.resolve_entities(entity_service)
  #   triples = TripleTransformer.new.transform(result)
  #
  class QueryResult
    attr_reader :query, :facts, :entities, :metadata, :raw_facts

    def initialize(query:)
      @query = query
      @facts = []
      @raw_facts = []
      @entities = {}
      @metadata = {
        retrieved_at: Time.now,
        stores_queried: [:fact_db]
      }
    end

    # Add facts to the result set.
    #
    # @param facts [Array<Fact>, Array<Hash>] Facts to add
    # @return [void]
    def add_facts(facts)
      return if facts.nil? || facts.empty?

      @raw_facts += Array(facts)
      @facts += normalize_facts(facts)
    end

    # Resolve and cache entities mentioned in facts.
    #
    # @param entity_service [EntityService] Service to resolve entities
    # @return [void]
    def resolve_entities(entity_service = nil)
      entity_ids = collect_entity_ids
      return if entity_ids.empty?

      entity_ids.each do |id|
        next if @entities[id]

        entity = resolve_entity(entity_service, id)
        @entities[id] = normalize_entity(entity) if entity
      end
    end

    # Check if results are empty.
    #
    # @return [Boolean]
    def empty?
      @facts.empty?
    end

    # Get all items for comparison operations.
    #
    # @return [Array<Hash>] Normalized items
    def items
      @facts.map { |f| normalize_for_comparison(f) }
    end

    # Convert to hash for JSON serialization.
    #
    # @return [Hash]
    def to_h
      {
        query: @query,
        facts: @facts,
        entities: @entities,
        metadata: @metadata
      }
    end

    # Hash-like access for backward compatibility.
    #
    # @param key [Symbol, String] Key to access
    # @return [Object] Value for the key
    def [](key)
      to_h[key.to_sym]
    end

    # Iterate over all facts.
    #
    # @yield [Hash] Each normalized fact
    # @return [void]
    def each_fact(&block)
      @facts.each(&block)
    end

    # Iterate over all entities.
    #
    # @yield [Hash] Each normalized entity
    # @return [void]
    def each_entity(&block)
      @entities.values.each(&block)
    end

    # Get count of facts.
    #
    # @return [Integer]
    def fact_count
      @facts.size
    end

    # Get count of entities.
    #
    # @return [Integer]
    def entity_count
      @entities.size
    end

    private

    def normalize_facts(facts)
      facts.map do |fact|
        if fact.is_a?(Hash)
          fact
        elsif fact.respond_to?(:as_json)
          fact.as_json.transform_keys(&:to_sym)
        else
          {
            id: fact.id,
            fact_text: fact.fact_text,
            valid_at: fact.valid_at,
            invalid_at: fact.invalid_at,
            status: fact.status,
            confidence: fact.respond_to?(:confidence) ? fact.confidence : nil,
            entity_mentions: extract_mentions(fact)
          }
        end
      end
    end

    def extract_mentions(fact)
      return [] unless fact.respond_to?(:entity_mentions)

      fact.entity_mentions.map do |mention|
        if mention.is_a?(Hash)
          mention
        else
          {
            entity_id: mention.entity_id,
            mention_role: mention.mention_role,
            mention_text: mention.respond_to?(:mention_text) ? mention.mention_text : nil,
            confidence: mention.respond_to?(:confidence) ? mention.confidence : nil
          }
        end
      end
    end

    def normalize_entity(entity)
      if entity.is_a?(Hash)
        entity
      elsif entity.respond_to?(:as_json)
        entity.as_json.transform_keys(&:to_sym)
      else
        {
          id: entity.id,
          name: entity.name,
          type: entity.type,
          aliases: entity.respond_to?(:aliases) ? entity.aliases.map { |a| { name: a.name, type: a.type } } : [],
          resolution_status: entity.respond_to?(:resolution_status) ? entity.resolution_status : nil
        }
      end
    end

    def collect_entity_ids
      ids = Set.new

      @facts.each do |fact|
        mentions = fact[:entity_mentions] || []
        mentions.each { |m| ids << m[:entity_id] }
      end

      ids.to_a.compact
    end

    def resolve_entity(entity_service, id)
      return nil unless entity_service

      if entity_service.respond_to?(:find)
        entity_service.find(id)
      end
    rescue StandardError
      nil
    end

    def normalize_for_comparison(item)
      {
        type: :fact,
        text: item[:fact_text],
        valid_at: item[:valid_at]
      }
    end
  end
end
