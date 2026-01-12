# frozen_string_literal: true

module FactDb
  module Services
    class FactService
      attr_reader :config, :resolver, :entity_service

      def initialize(config = FactDb.config)
        @config = config
        @resolver = Resolution::FactResolver.new(config)
        @entity_service = EntityService.new(config)
      end

      def create(text, valid_at:, invalid_at: nil, status: :canonical, source_id: nil, mentions: [], extraction_method: :manual, confidence: 1.0, metadata: {})
        embedding = generate_embedding(text)

        fact = Models::Fact.create!(
          fact_text: text,
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
          fact.add_source(source: source, type: "primary")
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

      def find_or_create(text, valid_at:, invalid_at: nil, status: :canonical, source_id: nil, mentions: [], extraction_method: :manual, confidence: 1.0, metadata: {})
        fact_hash = Digest::SHA256.hexdigest(text)
        existing = Models::Fact.find_by(fact_hash: fact_hash, valid_at: valid_at)

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

      def find(id)
        Models::Fact.find(id)
      end

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

      def query(topic: nil, at: nil, entity: nil, status: :canonical, limit: nil)
        Temporal::Query.new.execute(
          topic: topic,
          at: at,
          entity_id: entity,
          status: status,
          limit: limit
        )
      end

      def current_facts(entity: nil, topic: nil, limit: nil)
        query(topic: topic, entity: entity, at: nil, status: :canonical, limit: limit)
      end

      def facts_at(date, entity: nil, topic: nil)
        query(topic: topic, entity: entity, at: date, status: :canonical)
      end

      def timeline(entity_id:, from: nil, to: nil)
        Temporal::Timeline.new.build(entity_id: entity_id, from: from, to: to)
      end

      def supersede(old_fact_id, new_fact_text, valid_at:, mentions: [])
        @resolver.supersede(old_fact_id, new_fact_text, valid_at: valid_at, mentions: mentions)
      end

      def synthesize(source_fact_ids, synthesized_text, valid_at:, invalid_at: nil, mentions: [])
        @resolver.synthesize(source_fact_ids, synthesized_text, valid_at: valid_at, invalid_at: invalid_at, mentions: mentions)
      end

      def invalidate(fact_id, at: Time.current)
        @resolver.invalidate(fact_id, at: at)
      end

      def corroborate(fact_id, corroborating_fact_id)
        @resolver.corroborate(fact_id, corroborating_fact_id)
      end

      def search(query, entity: nil, status: :canonical, limit: 20)
        scope = Models::Fact.search_text(query)
        scope = apply_filters(scope, entity: entity, status: status)
        scope.order(valid_at: :desc).limit(limit)
      end

      def semantic_search(query, entity: nil, at: nil, limit: 20)
        embedding = generate_embedding(query)
        return Models::Fact.none unless embedding

        scope = Models::Fact.canonical.nearest_neighbors(embedding, limit: limit * 2)
        scope = scope.currently_valid if at.nil?
        scope = scope.valid_at(at) if at
        scope = scope.mentioning_entity(entity) if entity
        scope.limit(limit)
      end

      def find_conflicts(entity_id: nil, topic: nil)
        @resolver.find_conflicts(entity_id: entity_id, topic: topic)
      end

      def resolve_conflict(keep_fact_id, supersede_fact_ids, reason: nil)
        @resolver.resolve_conflict(keep_fact_id, supersede_fact_ids, reason: reason)
      end

      def build_timeline_fact(entity_id:, topic: nil)
        @resolver.build_timeline_fact(entity_id: entity_id, topic: topic)
      end

      def recent(limit: 10, status: :canonical)
        scope = Models::Fact.where(status: status.to_s).order(created_at: :desc)
        scope.limit(limit)
      end

      def by_extraction_method(method, limit: nil)
        scope = Models::Fact.extracted_by(method.to_s).order(created_at: :desc)
        scope = scope.limit(limit) if limit
        scope
      end

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

      # Get fact statistics for an entity (or all facts)
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
        type = mention[:type]&.to_sym || :concept
        aliases = mention[:aliases] || []

        entity = @entity_service.resolve_or_create(name, type: type, aliases: aliases)

        # If entity was resolved (not created), still add any new aliases
        add_aliases_to_entity(entity, aliases) if aliases.any?

        entity
      end

      def add_aliases_to_entity(entity, aliases)
        return unless aliases&.any?

        aliases.each do |alias_text|
          next if alias_text.to_s.strip.empty?
          next if entity.canonical_name.downcase == alias_text.to_s.strip.downcase
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
