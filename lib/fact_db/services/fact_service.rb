# frozen_string_literal: true

module FactDb
  module Services
    # Service class for managing facts in the database
    #
    # Provides methods for creating, querying, and manipulating facts
    # including temporal queries, semantic search, and conflict resolution.
    #
    # @example Basic usage
    #   service = FactService.new
    #   fact = service.create("John works at Acme", valid_at: Date.today)
    #
    class FactService
      # @return [FactDb::Config] the configuration object
      attr_reader :config

      # @return [FactDb::Resolution::FactResolver] the fact resolver instance
      attr_reader :resolver

      # @return [FactDb::Services::EntityService] the entity service instance
      attr_reader :entity_service

      # Initializes a new FactService instance
      #
      # @param config [FactDb::Config] configuration object (defaults to FactDb.config)
      def initialize(config = FactDb.config)
        @config = config
        @resolver = Resolution::FactResolver.new(config)
        @entity_service = EntityService.new(config)
      end

      # Creates a new fact in the database
      #
      # @param text [String] the fact text content
      # @param valid_at [Date, Time] when the fact became valid
      # @param invalid_at [Date, Time, nil] when the fact became invalid (nil if still valid)
      # @param status [Symbol] fact status (:canonical, :superseded, :synthesized)
      # @param source_id [Integer, nil] ID of the source document
      # @param mentions [Array<Hash>] entity mentions with :name, :kind, :role, :confidence keys
      # @param extraction_method [Symbol] how the fact was extracted (:manual, :llm, :rule_based)
      # @param confidence [Float] confidence score from 0.0 to 1.0
      # @param metadata [Hash] additional metadata for the fact
      # @return [FactDb::Models::Fact] the created fact
      #
      # @example Create a fact with mentions
      #   service.create(
      #     "John works at Acme Corp",
      #     valid_at: Date.parse("2024-01-15"),
      #     mentions: [
      #       { name: "John", kind: :person, role: :subject },
      #       { name: "Acme Corp", kind: :organization, role: :object }
      #     ]
      #   )
      def create(text, valid_at:, invalid_at: nil, status: :canonical, source_id: nil, mentions: [], extraction_method: :manual, confidence: 1.0, metadata: {})
        embedding = generate_embedding(text)

        fact = Models::Fact.create!(
          text: text,
          valid_at: valid_at,
          invalid_at: invalid_at,
          status: status.to_s,
          extraction_method: extraction_method.to_s,
          confidence: confidence,
          metadata: metadata,
          embedding: embedding
        )

        # Link to source
        if source_id
          source = Models::Source.find(source_id)
          fact.add_source(source: source, kind: "primary")
        end

        # Add entity mentions
        mentions.each do |mention|
          entity = resolve_or_create_entity(mention)
          fact.add_mention(
            entity: entity,
            text: mention[:text] || mention[:name],
            role: mention[:role],
            confidence: mention[:confidence] || 1.0
          )
        end

        fact
      end

      # Finds an existing fact or creates a new one
      #
      # Uses a SHA256 digest of the text and valid_at date to find duplicates.
      #
      # @param text [String] the fact text content
      # @param valid_at [Date, Time] when the fact became valid
      # @param invalid_at [Date, Time, nil] when the fact became invalid
      # @param status [Symbol] fact status
      # @param source_id [Integer, nil] ID of the source document
      # @param mentions [Array<Hash>] entity mentions
      # @param extraction_method [Symbol] extraction method used
      # @param confidence [Float] confidence score
      # @param metadata [Hash] additional metadata
      # @return [FactDb::Models::Fact] the found or created fact
      def find_or_create(text, valid_at:, invalid_at: nil, status: :canonical, source_id: nil, mentions: [], extraction_method: :manual, confidence: 1.0, metadata: {})
        digest = Digest::SHA256.hexdigest(text)
        existing = Models::Fact.find_by(digest: digest, valid_at: valid_at)

        return existing if existing

        create(
          text,
          valid_at: valid_at,
          invalid_at: invalid_at,
          status: status,
          source_id: source_id,
          mentions: mentions,
          extraction_method: extraction_method,
          confidence: confidence,
          metadata: metadata
        )
      end

      # Finds a fact by ID
      #
      # @param id [Integer] the fact ID
      # @return [FactDb::Models::Fact] the found fact
      # @raise [ActiveRecord::RecordNotFound] if fact not found
      def find(id)
        Models::Fact.find(id)
      end

      # Extracts facts from a source document
      #
      # Uses the configured extractor to parse the source content and create facts.
      #
      # @param source_id [Integer] ID of the source to extract from
      # @param extractor [Symbol] extractor type (:manual, :llm, :rule_based)
      # @return [Array<FactDb::Models::Fact>] array of created facts
      #
      # @example Extract facts using LLM
      #   facts = service.extract_from_source(source.id, extractor: :llm)
      def extract_from_source(source_id, extractor: config.default_extractor)
        source = Models::Source.find(source_id)
        extractor_instance = Extractors::Base.for(extractor, config)

        extracted = extractor_instance.extract(
          source.content,
          { captured_at: source.captured_at }
        )

        extracted.map do |fact_data|
          create(
            fact_data[:text],
            valid_at: fact_data[:valid_at],
            invalid_at: fact_data[:invalid_at],
            source_id: source_id,
            mentions: fact_data[:mentions],
            extraction_method: fact_data[:extraction_method] || extractor,
            confidence: fact_data[:confidence] || 1.0,
            metadata: fact_data[:metadata] || {}
          )
        end
      end

      # Alias for backward compatibility
      alias extract_from_content extract_from_source

      # Queries facts with filtering options
      #
      # @param topic [String, nil] topic to search for in fact text
      # @param at [Date, Time, nil] point in time for temporal query
      # @param entity [Integer, nil] entity ID to filter by
      # @param status [Symbol] fact status filter (:canonical, :superseded, :all)
      # @param limit [Integer, nil] maximum number of results
      # @return [ActiveRecord::Relation] matching facts
      #
      # @example Query facts about a topic at a specific date
      #   service.query(topic: "employment", at: Date.parse("2024-01-15"))
      def query(topic: nil, at: nil, entity: nil, status: :canonical, limit: nil)
        Temporal::Query.new.execute(
          topic: topic,
          at: at,
          entity_id: entity,
          status: status,
          limit: limit
        )
      end

      # Returns currently valid facts
      #
      # @param entity [Integer, nil] entity ID to filter by
      # @param topic [String, nil] topic to search for
      # @param limit [Integer, nil] maximum number of results
      # @return [ActiveRecord::Relation] currently valid canonical facts
      def current_facts(entity: nil, topic: nil, limit: nil)
        query(topic: topic, entity: entity, at: nil, status: :canonical, limit: limit)
      end

      # Returns facts valid at a specific date
      #
      # @param date [Date, Time] the point in time
      # @param entity [Integer, nil] entity ID to filter by
      # @param topic [String, nil] topic to search for
      # @return [ActiveRecord::Relation] facts valid at the given date
      def facts_at(date, entity: nil, topic: nil)
        query(topic: topic, entity: entity, at: date, status: :canonical)
      end

      # Builds a timeline of facts for an entity
      #
      # @param entity_id [Integer] the entity ID
      # @param from [Date, Time, nil] start of timeline range
      # @param to [Date, Time, nil] end of timeline range
      # @return [FactDb::Temporal::Timeline] timeline of facts
      #
      # @example Get timeline for past year
      #   service.timeline(entity_id: 1, from: 1.year.ago, to: Date.today)
      def timeline(entity_id:, from: nil, to: nil)
        Temporal::Timeline.new.build(entity_id: entity_id, from: from, to: to)
      end

      # Supersedes an old fact with new information
      #
      # Marks the old fact as superseded and creates a new canonical fact.
      #
      # @param old_fact_id [Integer] ID of the fact to supersede
      # @param new_text [String] the updated fact text
      # @param valid_at [Date, Time] when the new fact became valid
      # @param mentions [Array<Hash>] entity mentions for the new fact
      # @return [FactDb::Models::Fact] the new fact
      def supersede(old_fact_id, new_text, valid_at:, mentions: [])
        @resolver.supersede(old_fact_id, new_text, valid_at: valid_at, mentions: mentions)
      end

      # Synthesizes multiple facts into a single summary fact
      #
      # @param source_fact_ids [Array<Integer>] IDs of facts to synthesize
      # @param synthesized_text [String] the synthesized summary text
      # @param valid_at [Date, Time] when the synthesis is valid from
      # @param invalid_at [Date, Time, nil] when the synthesis becomes invalid
      # @param mentions [Array<Hash>] entity mentions for the synthesized fact
      # @return [FactDb::Models::Fact] the synthesized fact
      def synthesize(source_fact_ids, synthesized_text, valid_at:, invalid_at: nil, mentions: [])
        @resolver.synthesize(source_fact_ids, synthesized_text, valid_at: valid_at, invalid_at: invalid_at, mentions: mentions)
      end

      # Invalidates a fact at a specific time
      #
      # @param fact_id [Integer] ID of the fact to invalidate
      # @param at [Time] when the fact became invalid (defaults to now)
      # @return [FactDb::Models::Fact] the invalidated fact
      def invalidate(fact_id, at: Time.current)
        @resolver.invalidate(fact_id, at: at)
      end

      # Links a corroborating fact to support another fact
      #
      # @param fact_id [Integer] ID of the fact being corroborated
      # @param corroborating_fact_id [Integer] ID of the supporting fact
      # @return [FactDb::Models::Fact] the updated fact
      def corroborate(fact_id, corroborating_fact_id)
        @resolver.corroborate(fact_id, corroborating_fact_id)
      end

      # Searches facts using full-text search
      #
      # @param query [String] the search query
      # @param entity [Integer, nil] entity ID to filter by
      # @param status [Symbol] fact status filter
      # @param limit [Integer] maximum number of results
      # @return [ActiveRecord::Relation] matching facts
      def search(query, entity: nil, status: :canonical, limit: 20)
        scope = Models::Fact.search_text(query)
        scope = apply_filters(scope, entity: entity, status: status)
        scope.order(valid_at: :desc).limit(limit)
      end

      # Searches facts using semantic similarity (vector search)
      #
      # Requires an embedding generator to be configured.
      #
      # @param query [String] the search query
      # @param entity [Integer, nil] entity ID to filter by
      # @param at [Date, Time, nil] point in time for temporal filtering
      # @param limit [Integer] maximum number of results
      # @return [ActiveRecord::Relation] semantically similar facts
      #
      # @example Find semantically similar facts
      #   service.semantic_search("Who manages the sales team?", limit: 5)
      def semantic_search(query, entity: nil, at: nil, limit: 20)
        embedding = generate_embedding(query)
        return Models::Fact.none unless embedding

        scope = Models::Fact.canonical.nearest_neighbors(embedding, limit: limit * 2)
        scope = scope.currently_valid if at.nil?
        scope = scope.valid_at(at) if at
        scope = scope.mentioning_entity(entity) if entity
        scope.limit(limit)
      end

      # Finds conflicting facts for an entity or topic
      #
      # @param entity_id [Integer, nil] entity ID to check
      # @param topic [String, nil] topic to check
      # @return [Array<Hash>] array of conflict descriptions
      def find_conflicts(entity_id: nil, topic: nil)
        @resolver.find_conflicts(entity_id: entity_id, topic: topic)
      end

      # Resolves a conflict by keeping one fact and superseding others
      #
      # @param keep_fact_id [Integer] ID of the fact to keep
      # @param supersede_fact_ids [Array<Integer>] IDs of facts to supersede
      # @param reason [String, nil] reason for the resolution
      # @return [FactDb::Models::Fact] the kept fact
      def resolve_conflict(keep_fact_id, supersede_fact_ids, reason: nil)
        @resolver.resolve_conflict(keep_fact_id, supersede_fact_ids, reason: reason)
      end

      # Builds a timeline fact summarizing an entity's history
      #
      # @param entity_id [Integer] the entity ID
      # @param topic [String, nil] optional topic filter
      # @return [Hash] timeline summary data
      def build_timeline_fact(entity_id:, topic: nil)
        @resolver.build_timeline_fact(entity_id: entity_id, topic: topic)
      end

      # Returns recently created facts
      #
      # @param limit [Integer] maximum number of results
      # @param status [Symbol] fact status filter
      # @return [ActiveRecord::Relation] recent facts ordered by creation date
      def recent(limit: 10, status: :canonical)
        scope = Models::Fact.where(status: status.to_s).order(created_at: :desc)
        scope.limit(limit)
      end

      # Returns facts by extraction method
      #
      # @param method [Symbol, String] extraction method (:manual, :llm, :rule_based)
      # @param limit [Integer, nil] maximum number of results
      # @return [ActiveRecord::Relation] facts extracted by the given method
      def by_extraction_method(method, limit: nil)
        scope = Models::Fact.extracted_by(method.to_s).order(created_at: :desc)
        scope = scope.limit(limit) if limit
        scope
      end

      # Returns aggregate statistics about all facts
      #
      # @return [Hash] statistics including counts by status and extraction method
      def stats
        {
          total: Models::Fact.count,
          total_count: Models::Fact.count,
          canonical_count: Models::Fact.canonical.count,
          currently_valid_count: Models::Fact.canonical.currently_valid.count,
          by_status: Models::Fact.group(:status).count,
          by_extraction_method: Models::Fact.group(:extraction_method).count,
          average_confidence: Models::Fact.average(:confidence)&.to_f&.round(3)
        }
      end

      # Returns fact statistics for an entity (or all facts)
      #
      # @param entity_id [Integer, nil] Entity ID (nil for all facts)
      # @return [Hash] Statistics by fact status
      def fact_stats(entity_id = nil)
        scope = entity_id ? Models::Fact.mentioning_entity(entity_id) : Models::Fact.all

        {
          canonical: scope.where(status: "canonical").count,
          superseded: scope.where(status: "superseded").count,
          corroborated: scope.where.not(corroborated_by_ids: nil).where.not(corroborated_by_ids: []).count,
          synthesized: scope.where(status: "synthesized").count
        }
      end

      private

      def resolve_or_create_entity(mention)
        # If entity_id is already provided, use that entity directly
        if mention[:entity_id]
          entity = Models::Entity.find(mention[:entity_id])
          # Still add any new aliases even for existing entities
          add_aliases_to_entity(entity, mention[:aliases])
          return entity
        end

        name = mention[:name] || mention[:text]
        kind = mention[:kind]&.to_sym || :concept
        aliases = mention[:aliases] || []

        entity = @entity_service.resolve_or_create(name, kind: kind, aliases: aliases)

        # If entity was resolved (not created), still add any new aliases
        add_aliases_to_entity(entity, aliases) if aliases.any?

        entity
      end

      def add_aliases_to_entity(entity, aliases)
        return unless aliases&.any?

        aliases.each do |alias_text|
          next if alias_text.to_s.strip.empty?
          next if entity.name.downcase == alias_text.to_s.strip.downcase
          next if entity.all_aliases.map(&:downcase).include?(alias_text.to_s.strip.downcase)

          entity.add_alias(alias_text.to_s.strip)
        end
      end

      def apply_filters(scope, entity: nil, status: nil)
        scope = scope.mentioning_entity(entity) if entity
        scope = scope.where(status: status.to_s) if status && status != :all
        scope
      end

      def generate_embedding(text)
        return nil unless config.embedding_generator

        config.embedding_generator.call(text)
      rescue StandardError => e
        config.logger&.warn("Failed to generate embedding: #{e.message}")
        nil
      end
    end
  end
end
