# frozen_string_literal: true

module FactDb
  module Models
    class Entity < ActiveRecord::Base
      self.table_name = "fact_db_entities"

      has_many :aliases, class_name: "FactDb::Models::EntityAlias",
               foreign_key: :entity_id, dependent: :destroy
      has_many :entity_mentions, class_name: "FactDb::Models::EntityMention",
               foreign_key: :entity_id, dependent: :destroy
      has_many :facts, through: :entity_mentions

      belongs_to :merged_into, class_name: "FactDb::Models::Entity",
                 foreign_key: :merged_into_id, optional: true
      has_many :merged_entities, class_name: "FactDb::Models::Entity",
               foreign_key: :merged_into_id

      validates :canonical_name, presence: true
      validates :type, presence: true
      validates :resolution_status, presence: true

      STATUSES = %w[unresolved resolved merged split].freeze
      ENTITY_TYPES = %w[person organization place product event concept].freeze

      validates :resolution_status, inclusion: { in: STATUSES }
      validates :type, inclusion: { in: ENTITY_TYPES }

      scope :by_type, ->(t) { where(type: t) }
      scope :resolved, -> { where(resolution_status: "resolved") }
      scope :unresolved, -> { where(resolution_status: "unresolved") }
      scope :not_merged, -> { where.not(resolution_status: "merged") }

      def resolved?
        resolution_status == "resolved"
      end

      def merged?
        resolution_status == "merged"
      end

      def canonical_entity
        merged? ? merged_into&.canonical_entity || merged_into : self
      end

      def all_aliases
        aliases.pluck(:alias_text)
      end

      def add_alias(text, type: nil, confidence: 1.0)
        # Pre-validate before attempting to create
        return nil unless Validation::AliasFilter.valid?(text, canonical_name: canonical_name)

        aliases.find_or_create_by!(alias_text: text) do |a|
          a.alias_type = type
          a.confidence = confidence
        end
      rescue ActiveRecord::RecordInvalid
        # Alias validation failed (pronoun, generic term, etc.)
        nil
      end

      def matches_name?(name)
        return true if canonical_name.downcase == name.downcase

        aliases.exists?(["LOWER(alias_text) = ?", name.downcase])
      end

      # Get all facts mentioning this entity
      def current_facts
        facts.currently_valid.canonical
      end

      def facts_at(date)
        facts.valid_at(date).canonical
      end

      # Vector similarity search for entity matching
      def self.nearest_neighbors(embedding, limit: 10)
        return none unless embedding

        order(Arel.sql("embedding <=> '#{embedding}'")).limit(limit)
      end
    end
  end
end
