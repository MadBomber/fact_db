# frozen_string_literal: true

module FactDb
  module Services
    # Service class for managing entities in the database
    #
    # Provides methods for creating, searching, and managing entities including
    # name resolution, alias management, and duplicate detection.
    #
    # @example Basic usage
    #   service = EntityService.new
    #   entity = service.create("John Smith", kind: :person)
    #
    class EntityService
      # @return [FactDb::Config] the configuration object
      attr_reader :config

      # @return [FactDb::Resolution::EntityResolver] the entity resolver instance
      attr_reader :resolver

      # Initializes a new EntityService instance
      #
      # @param config [FactDb::Config] configuration object (defaults to FactDb.config)
      def initialize(config = FactDb.config)
        @config = config
        @resolver = Resolution::EntityResolver.new(config)
      end

      # Creates a new entity in the database
      #
      # @param name [String] the canonical name
      # @param kind [Symbol, String] entity kind (:person, :organization, etc.)
      # @param aliases [Array<String>] alternative names
      # @param attributes [Hash] additional metadata attributes
      # @param description [String, nil] entity description
      # @return [FactDb::Models::Entity] the created entity
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

      # Finds an entity by ID
      #
      # @param id [Integer] the entity ID
      # @return [FactDb::Models::Entity] the found entity
      # @raise [ActiveRecord::RecordNotFound] if entity not found
      def find(id)
        Models::Entity.find(id)
      end

      # Finds an entity by exact name match
      #
      # @param name [String] the entity name (case-insensitive)
      # @param kind [Symbol, String, nil] optional kind filter
      # @return [FactDb::Models::Entity, nil] the found entity or nil
      def find_by_name(name, kind: nil)
        scope = Models::Entity.where(["LOWER(name) = ?", name.downcase])
        scope = scope.where(kind: kind) if kind
        scope.not_merged.first
      end

      # Resolves a name to an existing entity
      #
      # Uses exact alias matching, canonical name matching, and fuzzy matching.
      #
      # @param name [String] the name to resolve
      # @param kind [Symbol, nil] optional kind filter
      # @return [FactDb::Resolution::ResolvedEntity, nil] resolved entity or nil
      def resolve(name, kind: nil)
        @resolver.resolve(name, kind: kind)
      end

      # Resolves a name to an entity, creating one if not found
      #
      # Also checks if any provided aliases match existing entities.
      #
      # @param name [String] the name to resolve or create
      # @param kind [Symbol, String] entity kind (required for creation)
      # @param aliases [Array<String>] additional aliases
      # @param attributes [Hash] additional attributes for new entity
      # @param description [String, nil] entity description
      # @return [FactDb::Models::Entity] the resolved or created entity
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

      # Merges two entities, keeping one as canonical
      #
      # @param keep_id [Integer] ID of the entity to keep
      # @param merge_id [Integer] ID of the entity to merge
      # @return [FactDb::Models::Entity] the kept entity
      def merge(keep_id, merge_id)
        @resolver.merge(keep_id, merge_id)
      end

      # Adds an alias to an entity
      #
      # @param entity_id [Integer] the entity ID
      # @param alias_name [String] the alias text
      # @param kind [String, nil] alias kind
      # @param confidence [Float] confidence score
      # @return [FactDb::Models::EntityAlias] the created alias
      def add_alias(entity_id, alias_name, kind: nil, confidence: 1.0)
        entity = Models::Entity.find(entity_id)
        entity.add_alias(alias_name, kind: kind, confidence: confidence)
      end

      # Searches entities by name or alias using LIKE pattern matching
      #
      # @param query [String] the search query
      # @param kind [Symbol, String, nil] optional kind filter
      # @param limit [Integer] maximum number of results
      # @return [ActiveRecord::Relation] matching entities
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

      # Searches entities using semantic similarity (vector search)
      #
      # Requires an embedding generator to be configured.
      #
      # @param query [String] the search query
      # @param kind [Symbol, String, nil] optional kind filter
      # @param limit [Integer] maximum number of results
      # @return [ActiveRecord::Relation] semantically similar entities
      def semantic_search(query, kind: nil, limit: 20)
        embedding = generate_embedding(query)
        return Models::Entity.none unless embedding

        scope = Models::Entity.not_merged.nearest_neighbors(embedding, limit: limit)
        scope = scope.where(kind: kind) if kind
        scope
      end

      # Searches entities using PostgreSQL trigram similarity (handles typos)
      #
      # Requires pg_trgm extension. Falls back to LIKE search if unavailable.
      #
      # @param query [String] search term (minimum 3 characters)
      # @param kind [Symbol, String, nil] optional kind filter
      # @param threshold [Float] minimum similarity score (0.0-1.0)
      # @param limit [Integer] maximum number of results
      # @return [Array<FactDb::Models::Entity>] entities ordered by similarity
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

      # Returns entities of a specific kind
      #
      # @param kind [Symbol, String] the entity kind
      # @return [ActiveRecord::Relation] entities of that kind
      def by_kind(kind)
        Models::Entity.by_kind(kind).not_merged.order(:name)
      end

      # Returns facts about an entity
      #
      # @param entity_id [Integer] the entity ID
      # @param at [Date, Time, nil] optional point in time
      # @param status [Symbol] fact status filter
      # @return [ActiveRecord::Relation] facts mentioning the entity
      def facts_about(entity_id, at: nil, status: :canonical)
        Temporal::Query.new.execute(
          entity_id: entity_id,
          at: at,
          status: status
        )
      end

      # Builds a timeline of facts for an entity
      #
      # @param entity_id [Integer] the entity ID
      # @param from [Date, Time, nil] start of timeline range
      # @param to [Date, Time, nil] end of timeline range
      # @return [FactDb::Temporal::Timeline] timeline of facts
      def timeline_for(entity_id, from: nil, to: nil)
        Temporal::Timeline.new.build(entity_id: entity_id, from: from, to: to)
      end

      # Finds potential duplicate entities
      #
      # @param threshold [Float, nil] minimum similarity score
      # @return [Array<Hash>] array of potential duplicates
      def find_duplicates(threshold: nil)
        @resolver.find_duplicates(threshold: threshold)
      end

      # Automatically merges high-confidence duplicates
      #
      # @return [void]
      def auto_merge_duplicates!
        @resolver.auto_merge_duplicates!
      end

      # Returns aggregate statistics about entities
      #
      # @return [Hash] statistics including counts by kind and status
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

      # Returns all relationship types used in the database
      #
      # @return [Array<Symbol>] relationship types (mention roles)
      def relationship_types
        Models::EntityMention.distinct.pluck(:mention_role).compact.map(&:to_sym)
      end

      # Returns relationship types for a specific entity
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

      # Returns the timespan of facts for an entity
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
