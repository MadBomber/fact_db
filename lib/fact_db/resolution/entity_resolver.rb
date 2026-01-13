# frozen_string_literal: true

module FactDb
  module Resolution
    # Resolves entity names to canonical entities in the database
    #
    # Provides entity resolution through exact alias matching, canonical name matching,
    # and fuzzy matching using Levenshtein distance. Also handles entity merging,
    # splitting, and duplicate detection.
    #
    # @example Basic usage
    #   resolver = EntityResolver.new
    #   resolved = resolver.resolve("John Smith", kind: :person)
    #   if resolved
    #     puts "Found: #{resolved.entity.name} (confidence: #{resolved.confidence})"
    #   end
    #
    class EntityResolver
      # @return [FactDb::Config] the configuration object
      attr_reader :config

      # Initializes a new EntityResolver instance
      #
      # @param config [FactDb::Config] configuration object (defaults to FactDb.config)
      def initialize(config = FactDb.config)
        @config = config
        @threshold = config.fuzzy_match_threshold
        @auto_merge_threshold = config.auto_merge_threshold
      end

      # Resolves a name to an existing entity
      #
      # Tries resolution in order: exact alias match, canonical name match, fuzzy match.
      #
      # @param name [String] the name to resolve
      # @param kind [Symbol, nil] optional entity kind filter (:person, :organization, etc.)
      # @return [ResolvedEntity, nil] resolved entity with confidence score, or nil if not found
      #
      # @example Resolve with kind filter
      #   resolver.resolve("Acme", kind: :organization)
      def resolve(name, kind: nil)
        return nil if name.nil? || name.empty?

        # 1. Exact alias match
        exact = find_by_exact_alias(name, kind: kind)
        return ResolvedEntity.new(exact, confidence: 1.0, match_type: :exact_alias) if exact

        # 2. Canonical name match
        canonical = find_by_name(name, kind: kind)
        return ResolvedEntity.new(canonical, confidence: 1.0, match_type: :name) if canonical

        # 3. Fuzzy matching
        fuzzy = find_by_fuzzy_match(name, kind: kind)
        return fuzzy if fuzzy && fuzzy.confidence >= @threshold

        # 4. No match found
        nil
      end

      # Resolves a name to an entity, creating one if not found
      #
      # @param name [String] the name to resolve or create
      # @param kind [Symbol] the entity kind (required for creation)
      # @param aliases [Array<String>] additional aliases to add
      # @param attributes [Hash] additional attributes for new entity
      # @return [FactDb::Models::Entity] the resolved or created entity
      #
      # @example Create with aliases
      #   resolver.resolve_or_create("John Smith", kind: :person, aliases: ["J. Smith", "Johnny"])
      def resolve_or_create(name, kind:, aliases: [], attributes: {})
        resolved = resolve(name, kind: kind)
        return resolved.entity if resolved

        create_entity(name, kind: kind, aliases: aliases, attributes: attributes)
      end

      # Merges two entities, keeping one as canonical
      #
      # Transfers all aliases and mentions from the merged entity to the kept entity.
      #
      # @param keep_id [Integer] ID of the entity to keep
      # @param merge_id [Integer] ID of the entity to merge (will be marked as merged)
      # @return [FactDb::Models::Entity] the kept entity with updated aliases
      # @raise [ResolutionError] if attempting to merge into itself or merge already merged entity
      #
      # @example Merge duplicate entities
      #   resolver.merge(primary_entity.id, duplicate_entity.id)
      def merge(keep_id, merge_id)
        keep = Models::Entity.find(keep_id)
        merge_entity = Models::Entity.find(merge_id)

        raise ResolutionError, "Cannot merge entity into itself" if keep_id == merge_id
        raise ResolutionError, "Cannot merge already merged entity" if merge_entity.merged?

        Models::Entity.transaction do
          # Move all aliases to kept entity
          merge_entity.aliases.each do |alias_record|
            keep.aliases.find_or_create_by!(name: alias_record.name) do |a|
              a.kind = alias_record.kind
              a.confidence = alias_record.confidence
            end
          end

          # Add the merged entity's canonical name as an alias
          keep.aliases.find_or_create_by!(name: merge_entity.name) do |a|
            a.kind = "name"
            a.confidence = 1.0
          end

          # Update all entity mentions to point to kept entity
          Models::EntityMention.where(entity_id: merge_id).update_all(entity_id: keep_id)

          # Mark merged entity
          merge_entity.update!(
            resolution_status: "merged",
            canonical_id: keep_id
          )
        end

        keep.reload
      end

      # Splits an entity into multiple new entities
      #
      # Creates new entities based on the split configuration and marks the original as split.
      #
      # @param entity_id [Integer] ID of the entity to split
      # @param split_configs [Array<Hash>] array of hashes with :name, :kind, :aliases, :attributes
      # @return [Array<FactDb::Models::Entity>] array of newly created entities
      #
      # @example Split an ambiguous entity
      #   resolver.split(entity.id, [
      #     { name: "John Smith (Sales)", kind: :person },
      #     { name: "John Smith (Engineering)", kind: :person }
      #   ])
      def split(entity_id, split_configs)
        original = Models::Entity.find(entity_id)

        Models::Entity.transaction do
          new_entities = split_configs.map do |config|
            create_entity(
              config[:name],
              kind: config[:kind] || original.kind,
              aliases: config[:aliases] || [],
              attributes: config[:attributes] || {}
            )
          end

          original.update!(resolution_status: "split")

          new_entities
        end
      end

      # Finds potential duplicate entities based on name similarity
      #
      # @param threshold [Float, nil] minimum similarity score (defaults to config threshold)
      # @return [Array<Hash>] array of hashes with :entity1, :entity2, :similarity keys
      #
      # @example Find duplicates with custom threshold
      #   duplicates = resolver.find_duplicates(threshold: 0.85)
      #   duplicates.each { |d| puts "#{d[:entity1].name} ~ #{d[:entity2].name} (#{d[:similarity]})" }
      def find_duplicates(threshold: nil)
        threshold ||= @threshold
        duplicates = []

        entities = Models::Entity.resolved.to_a

        entities.each_with_index do |entity, i|
          entities[(i + 1)..].each do |other|
            similarity = calculate_similarity(entity.name, other.name)
            if similarity >= threshold
              duplicates << {
                entity1: entity,
                entity2: other,
                similarity: similarity
              }
            end
          end
        end

        duplicates.sort_by { |d| -d[:similarity] }
      end

      # Automatically merges high-confidence duplicates
      #
      # Uses the auto_merge_threshold from config and keeps the entity with more mentions.
      #
      # @return [void]
      def auto_merge_duplicates!
        duplicates = find_duplicates(threshold: @auto_merge_threshold)

        duplicates.each do |dup|
          next if dup[:entity1].merged? || dup[:entity2].merged?

          # Keep the entity with more mentions
          keep, merge_entity = if dup[:entity1].entity_mentions.count >= dup[:entity2].entity_mentions.count
                                 [dup[:entity1], dup[:entity2]]
                               else
                                 [dup[:entity2], dup[:entity1]]
                               end

          merge(keep.id, merge_entity.id)
        end
      end

      private

      def find_by_exact_alias(name, kind:)
        scope = Models::EntityAlias.where(["LOWER(fact_db_entity_aliases.name) = ?", name.downcase])
        scope = scope.joins(:entity).where(fact_db_entities: { kind: kind }) if kind
        scope = scope.joins(:entity).where.not(fact_db_entities: { resolution_status: "merged" })
        scope.first&.entity
      end

      def find_by_name(name, kind:)
        scope = Models::Entity.where(["LOWER(name) = ?", name.downcase])
        scope = scope.where(kind: kind) if kind
        scope.not_merged.first
      end

      def find_by_fuzzy_match(name, kind:)
        candidates = Models::Entity.not_merged
        candidates = candidates.where(kind: kind) if kind

        best_match = nil
        best_similarity = 0

        candidates.find_each do |entity|
          # Check canonical name
          similarity = calculate_similarity(name, entity.name)
          if similarity > best_similarity
            best_similarity = similarity
            best_match = entity
          end

          # Check aliases
          entity.aliases.each do |alias_record|
            alias_similarity = calculate_similarity(name, alias_record.name)
            if alias_similarity > best_similarity
              best_similarity = alias_similarity
              best_match = entity
            end
          end
        end

        return nil if best_match.nil? || best_similarity < @threshold

        ResolvedEntity.new(best_match, confidence: best_similarity, match_type: :fuzzy)
      end

      def create_entity(name, kind:, aliases: [], attributes: {})
        entity = Models::Entity.create!(
          name: name,
          kind: kind,
          attributes: attributes,
          resolution_status: "resolved"
        )

        aliases.each do |alias_text|
          entity.add_alias(alias_text)
        end

        entity
      end

      def calculate_similarity(a, b)
        return 1.0 if a.downcase == b.downcase

        max_len = [a.length, b.length].max
        return 1.0 if max_len.zero?

        1.0 - (levenshtein_distance(a.downcase, b.downcase).to_f / max_len)
      end

      def levenshtein_distance(a, b)
        m = a.length
        n = b.length
        d = Array.new(m + 1) { |i| i }

        (1..n).each do |j|
          prev = d[0]
          d[0] = j
          (1..m).each do |i|
            temp = d[i]
            d[i] = if a[i - 1] == b[j - 1]
                     prev
                   else
                     [prev + 1, d[i] + 1, d[i - 1] + 1].min
                   end
            prev = temp
          end
        end

        d[m]
      end
    end

    # Represents a resolved entity with confidence metadata
    #
    # Wraps an entity with information about how it was resolved
    # and the confidence level of the match.
    #
    class ResolvedEntity
      # @return [FactDb::Models::Entity] the resolved entity
      attr_reader :entity

      # @return [Float] confidence score from 0.0 to 1.0
      attr_reader :confidence

      # @return [Symbol] how the entity was matched (:exact_alias, :name, :fuzzy)
      attr_reader :match_type

      # Initializes a new ResolvedEntity
      #
      # @param entity [FactDb::Models::Entity] the resolved entity
      # @param confidence [Float] confidence score (0.0 to 1.0)
      # @param match_type [Symbol] match type (:exact_alias, :name, :fuzzy)
      def initialize(entity, confidence:, match_type:)
        @entity = entity
        @confidence = confidence
        @match_type = match_type
      end

      # Checks if this was an exact match (confidence == 1.0)
      #
      # @return [Boolean] true if confidence is 1.0
      def exact_match?
        confidence == 1.0
      end

      # Checks if this was a fuzzy match
      #
      # @return [Boolean] true if match_type is :fuzzy
      def fuzzy_match?
        match_type == :fuzzy
      end

      # Returns the entity ID
      #
      # @return [Integer] the entity's database ID
      def id
        entity.id
      end

      # Returns the entity name
      #
      # @return [String] the entity's canonical name
      def name
        entity.name
      end

      # Returns the entity kind
      #
      # @return [String] the entity's kind
      def kind
        entity.kind
      end
    end
  end
end
