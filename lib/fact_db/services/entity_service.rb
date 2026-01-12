# frozen_string_literal: true

module FactDb
  module Services
    class EntityService
      attr_reader :config, :resolver

      def initialize(config = FactDb.config)
        @config = config
        @resolver = Resolution::EntityResolver.new(config)
      end

      def create(name, kind:, aliases: [], attributes: {}, description: nil)
        embedding = generate_embedding(name)

        entity = Models::Entity.create!(
          name: name,
          kind: kind.to_s,
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

      def find_by_name(name, kind: nil)
        scope = Models::Entity.where(["LOWER(name) = ?", name.downcase])
        scope = scope.where(kind: kind) if kind
        scope.not_merged.first
      end

      def resolve(name, kind: nil)
        @resolver.resolve(name, kind: kind)
      end

      def resolve_or_create(name, kind:, aliases: [], attributes: {}, description: nil)
        # First, try to resolve the canonical name
        resolved = @resolver.resolve(name, kind: kind)
        if resolved
          # Add any new aliases to the resolved entity
          add_new_aliases(resolved.entity, aliases)
          return resolved.entity
        end

        # Check if any of the provided aliases match an existing entity
        # This handles cases like: name="Lord", aliases=["Jesus"] where "Jesus" already exists
        aliases.each do |alias_text|
          next if alias_text.to_s.strip.empty?

          resolved_by_alias = @resolver.resolve(alias_text.to_s.strip, kind: kind)
          if resolved_by_alias
            entity = resolved_by_alias.entity
            # Add the new canonical name as an alias to the existing entity
            entity.add_alias(name) unless entity.name.downcase == name.downcase
            # Add all the other aliases too
            add_new_aliases(entity, aliases)
            return entity
          end
        end

        create(name, kind: kind, aliases: aliases, attributes: attributes, description: description)
      end

      def merge(keep_id, merge_id)
        @resolver.merge(keep_id, merge_id)
      end

      def add_alias(entity_id, alias_name, kind: nil, confidence: 1.0)
        entity = Models::Entity.find(entity_id)
        entity.add_alias(alias_name, kind: kind, confidence: confidence)
      end

      def search(query, kind: nil, limit: 20)
        scope = Models::Entity.not_merged

        # Search canonical names and aliases
        scope = scope.left_joins(:aliases).where(
          "LOWER(fact_db_entities.name) LIKE ? OR LOWER(fact_db_entity_aliases.name) LIKE ?",
          "%#{query.downcase}%",
          "%#{query.downcase}%"
        ).distinct

        scope = scope.where(kind: kind) if kind
        scope.limit(limit)
      end

      def semantic_search(query, kind: nil, limit: 20)
        embedding = generate_embedding(query)
        return Models::Entity.none unless embedding

        scope = Models::Entity.not_merged.nearest_neighbors(embedding, limit: limit)
        scope = scope.where(kind: kind) if kind
        scope
      end

      # Fuzzy search using PostgreSQL pg_trgm similarity
      # Returns entities where name or aliases are similar to the query
      # Requires pg_trgm extension and GIN trigram indexes
      #
      # @param query [String] Search term (handles misspellings)
      # @param type [Symbol, nil] Optional entity type filter
      # @param threshold [Float] Minimum similarity score (0.0-1.0, default 0.3)
      # @param limit [Integer] Maximum results to return
      # @return [Array<Entity>] Entities ordered by similarity score
      def fuzzy_search(query, kind: nil, threshold: 0.3, limit: 20)
        return [] if query.to_s.strip.length < 3

        sql = <<~SQL
          SELECT DISTINCT e.id,
                 GREATEST(
                   similarity(LOWER(e.name), LOWER(?)),
                   COALESCE(MAX(similarity(LOWER(a.name), LOWER(?))), 0)
                 ) as sim_score
          FROM fact_db_entities e
          LEFT JOIN fact_db_entity_aliases a ON a.entity_id = e.id
          WHERE e.resolution_status != 'merged'
            AND (
              similarity(LOWER(e.name), LOWER(?)) > ?
              OR similarity(LOWER(a.name), LOWER(?)) > ?
            )
          GROUP BY e.id
          ORDER BY sim_score DESC
          LIMIT ?
        SQL

        sanitized = ActiveRecord::Base.sanitize_sql(
          [sql, query, query, query, threshold, query, threshold, limit]
        )

        results = ActiveRecord::Base.connection.execute(sanitized)
        entity_ids = results.map { |r| r["id"] }

        return [] if entity_ids.empty?

        # Preserve ordering by fetching in order
        entities_by_id = Models::Entity.where(id: entity_ids).index_by(&:id)
        ordered_entities = entity_ids.map { |id| entities_by_id[id] }.compact

        # Apply kind filter if specified
        if kind
          ordered_entities = ordered_entities.select { |e| e.kind == kind.to_s }
        end

        ordered_entities
      rescue ActiveRecord::StatementInvalid => e
        # pg_trgm extension not available, fall back to LIKE search
        config.logger&.warn("Fuzzy search unavailable (pg_trgm not installed): #{e.message}")
        search(query, kind: kind, limit: limit).to_a
      end

      def by_kind(kind)
        Models::Entity.by_kind(kind).not_merged.order(:name)
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
          by_kind: Models::Entity.not_merged.group(:kind).count,
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
        valid_aliases = Validation::AliasFilter.filter(aliases, name: entity.name)

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
