# frozen_string_literal: true

module FactDb
  module Models
    # Represents a named entity in the fact database
    #
    # Entities are real-world things like people, organizations, places, etc.
    # that can be referenced in facts. Entities support aliases for name variations
    # and can be merged to deduplicate records.
    #
    # @example Create an entity with aliases
    #   entity = Entity.create!(name: "John Smith", kind: "person", resolution_status: "resolved")
    #   entity.add_alias("J. Smith")
    #
    # @example Find entities by kind
    #   people = Entity.by_kind("person").not_merged
    #
    class Entity < ActiveRecord::Base
      self.table_name = "fact_db_entities"

      has_many :aliases, class_name: "FactDb::Models::EntityAlias",
               foreign_key: :entity_id, dependent: :destroy
      has_many :entity_mentions, class_name: "FactDb::Models::EntityMention",
               foreign_key: :entity_id, dependent: :destroy
      has_many :facts, through: :entity_mentions

      belongs_to :canonical, class_name: "FactDb::Models::Entity",
                 foreign_key: :canonical_id, optional: true
      has_many :merged_entities, class_name: "FactDb::Models::Entity",
               foreign_key: :canonical_id

      validates :name, presence: true
      validates :kind, presence: true
      validates :resolution_status, presence: true

      # @return [Array<String>] valid resolution statuses
      STATUSES = %w[unresolved resolved merged split].freeze

      # @return [Array<String>] valid entity kinds
      ENTITY_KINDS = %w[person organization place product event concept other].freeze

      validates :resolution_status, inclusion: { in: STATUSES }
      validates :kind, inclusion: { in: ENTITY_KINDS }

      # @!method by_kind(k)
      #   Returns entities of a specific kind
      #   @param k [String] the entity kind
      #   @return [ActiveRecord::Relation]
      scope :by_kind, ->(k) { where(kind: k) }

      # @!method resolved
      #   Returns entities with "resolved" status
      #   @return [ActiveRecord::Relation]
      scope :resolved, -> { where(resolution_status: "resolved") }

      # @!method unresolved
      #   Returns entities with "unresolved" status
      #   @return [ActiveRecord::Relation]
      scope :unresolved, -> { where(resolution_status: "unresolved") }

      # @!method not_merged
      #   Returns entities that have not been merged
      #   @return [ActiveRecord::Relation]
      scope :not_merged, -> { where.not(resolution_status: "merged") }

      # Checks if the entity is resolved
      #
      # @return [Boolean] true if resolution_status is "resolved"
      def resolved?
        resolution_status == "resolved"
      end

      # Checks if the entity has been merged into another
      #
      # @return [Boolean] true if resolution_status is "merged"
      def merged?
        resolution_status == "merged"
      end

      # Returns the canonical entity (follows merge chain)
      #
      # If this entity has been merged, recursively follows the canonical_id
      # chain to find the ultimate canonical entity.
      #
      # @return [Entity] the canonical entity or self if not merged
      def canonical_entity
        merged? ? canonical&.canonical_entity || canonical : self
      end

      # Returns all alias names as an array of strings
      #
      # @return [Array<String>] alias names
      def all_aliases
        aliases.pluck(:name)
      end

      # Adds an alias to this entity
      #
      # Validates the alias before creation using AliasFilter.
      # Returns nil if validation fails.
      #
      # @param text [String] the alias text
      # @param kind [String, nil] alias kind (name, nickname, email, handle, abbreviation, title)
      # @param confidence [Float] confidence score (0.0 to 1.0)
      # @return [EntityAlias, nil] the created alias or nil if validation failed
      def add_alias(text, kind: nil, confidence: 1.0)
        # Pre-validate before attempting to create
        return nil unless Validation::AliasFilter.valid?(text, name: name)

        aliases.find_or_create_by!(name: text) do |a|
          a.kind = kind
          a.confidence = confidence
        end
      rescue ActiveRecord::RecordInvalid
        # Alias validation failed (pronoun, generic term, etc.)
        nil
      end

      # Checks if the entity matches a query (by name or alias)
      #
      # @param query [String] the name to match (case-insensitive)
      # @return [Boolean] true if name or any alias matches
      def matches_name?(query)
        return true if self.name.downcase == query.downcase

        aliases.exists?(["LOWER(name) = ?", query.downcase])
      end

      # Returns currently valid canonical facts mentioning this entity
      #
      # @return [ActiveRecord::Relation] currently valid facts
      def current_facts
        facts.currently_valid.canonical
      end

      # Returns facts valid at a specific date
      #
      # @param date [Date, Time] the point in time to query
      # @return [ActiveRecord::Relation] facts valid at the given date
      def facts_at(date)
        facts.valid_at(date).canonical
      end

      # Finds entities by vector similarity using pgvector
      #
      # @param embedding [Array<Float>] the embedding vector to search with
      # @param limit [Integer] maximum number of results
      # @return [ActiveRecord::Relation] entities ordered by similarity
      def self.nearest_neighbors(embedding, limit: 10)
        return none unless embedding

        order(Arel.sql("embedding <=> '#{embedding}'")).limit(limit)
      end
    end
  end
end
