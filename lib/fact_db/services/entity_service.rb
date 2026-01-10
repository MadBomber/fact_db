# frozen_string_literal: true

module FactDb
  module Services
    class EntityService
      attr_reader :config, :resolver

      def initialize(config = FactDb.config)
        @config = config
        @resolver = Resolution::EntityResolver.new(config)
      end

      def create(name, type:, aliases: [], attributes: {}, description: nil)
        embedding = generate_embedding(name)

        entity = Models::Entity.create!(
          canonical_name: name,
          entity_type: type.to_s,
          description: description,
          metadata: attributes,
          resolution_status: "resolved",
          embedding: embedding
        )

        aliases.each do |alias_text|
          entity.add_alias(alias_text)
        end

        entity
      end

      def find(id)
        Models::Entity.find(id)
      end

      def find_by_name(name, type: nil)
        scope = Models::Entity.where(["LOWER(canonical_name) = ?", name.downcase])
        scope = scope.where(entity_type: type) if type
        scope.not_merged.first
      end

      def resolve(name, type: nil)
        @resolver.resolve(name, type: type)
      end

      def resolve_or_create(name, type:, aliases: [], attributes: {}, description: nil)
        # First, try to resolve the canonical name
        resolved = @resolver.resolve(name, type: type)
        if resolved
          # Add any new aliases to the resolved entity
          add_new_aliases(resolved.entity, aliases)
          return resolved.entity
        end

        # Check if any of the provided aliases match an existing entity
        # This handles cases like: name="Lord", aliases=["Jesus"] where "Jesus" already exists
        aliases.each do |alias_text|
          next if alias_text.to_s.strip.empty?

          resolved_by_alias = @resolver.resolve(alias_text.to_s.strip, type: type)
          if resolved_by_alias
            entity = resolved_by_alias.entity
            # Add the new canonical name as an alias to the existing entity
            entity.add_alias(name) unless entity.canonical_name.downcase == name.downcase
            # Add all the other aliases too
            add_new_aliases(entity, aliases)
            return entity
          end
        end

        create(name, type: type, aliases: aliases, attributes: attributes, description: description)
      end

      def merge(keep_id, merge_id)
        @resolver.merge(keep_id, merge_id)
      end

      def add_alias(entity_id, alias_text, alias_type: nil, confidence: 1.0)
        entity = Models::Entity.find(entity_id)
        entity.add_alias(alias_text, type: alias_type, confidence: confidence)
      end

      def search(query, type: nil, limit: 20)
        scope = Models::Entity.not_merged

        # Search canonical names and aliases
        scope = scope.left_joins(:aliases).where(
          "LOWER(fact_db_entities.canonical_name) LIKE ? OR LOWER(fact_db_entity_aliases.alias_text) LIKE ?",
          "%#{query.downcase}%",
          "%#{query.downcase}%"
        ).distinct

        scope = scope.where(entity_type: type) if type
        scope.limit(limit)
      end

      def semantic_search(query, type: nil, limit: 20)
        embedding = generate_embedding(query)
        return Models::Entity.none unless embedding

        scope = Models::Entity.not_merged.nearest_neighbors(embedding, limit: limit)
        scope = scope.where(entity_type: type) if type
        scope
      end

      def by_type(type)
        Models::Entity.by_type(type).not_merged.order(:canonical_name)
      end

      def facts_about(entity_id, at: nil, status: :canonical)
        Temporal::Query.new.execute(
          entity_id: entity_id,
          at: at,
          status: status
        )
      end

      def timeline_for(entity_id, from: nil, to: nil)
        Temporal::Timeline.new.build(entity_id: entity_id, from: from, to: to)
      end

      def find_duplicates(threshold: nil)
        @resolver.find_duplicates(threshold: threshold)
      end

      def auto_merge_duplicates!
        @resolver.auto_merge_duplicates!
      end

      def stats
        {
          total: Models::Entity.not_merged.count,
          total_count: Models::Entity.not_merged.count,
          by_type: Models::Entity.not_merged.group(:entity_type).count,
          by_status: Models::Entity.group(:resolution_status).count,
          merged_count: Models::Entity.where(resolution_status: "merged").count,
          with_facts: Models::Entity.joins(:entity_mentions).distinct.count
        }
      end

      # Get all relationship types used in the database
      #
      # @return [Array<Symbol>] Relationship types (mention roles)
      def relationship_types
        Models::EntityMention.distinct.pluck(:mention_role).compact.map(&:to_sym)
      end

      # Get relationship types for a specific entity
      #
      # @param entity_id [Integer] Entity ID
      # @return [Array<Symbol>] Relationship types for this entity
      def relationship_types_for(entity_id)
        Models::EntityMention
          .where(entity_id: entity_id)
          .distinct
          .pluck(:mention_role)
          .compact
          .map(&:to_sym)
      end

      # Get the timespan of facts for an entity
      #
      # @param entity_id [Integer] Entity ID
      # @return [Hash] Hash with :from and :to dates
      def timespan_for(entity_id)
        facts = Models::Fact
          .joins(:entity_mentions)
          .where(entity_mentions: { entity_id: entity_id })

        {
          from: facts.minimum(:valid_at),
          to: facts.maximum(:valid_at) || Date.today
        }
      end

      private

      def add_new_aliases(entity, aliases)
        return unless aliases&.any?

        # Filter out pronouns and generic terms
        valid_aliases = Validation::AliasFilter.filter(aliases, canonical_name: entity.canonical_name)

        valid_aliases.each do |alias_text|
          next if entity.all_aliases.map(&:downcase).include?(alias_text.downcase)

          entity.add_alias(alias_text)
        end
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
