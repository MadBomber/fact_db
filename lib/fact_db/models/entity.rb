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

      belongs_to :canonical, class_name: "FactDb::Models::Entity",
                 foreign_key: :canonical_id, optional: true
      has_many :merged_entities, class_name: "FactDb::Models::Entity",
               foreign_key: :canonical_id

      validates :name, presence: true
      validates :kind, presence: true
      validates :resolution_status, presence: true

      STATUSES = %w[unresolved resolved merged split].freeze
      ENTITY_KINDS = %w[person organization place product event concept].freeze

      validates :resolution_status, inclusion: { in: STATUSES }
      validates :kind, inclusion: { in: ENTITY_KINDS }

      scope :by_kind, ->(k) { where(kind: k) }
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
        merged? ? canonical&.canonical_entity || canonical : self
      end

      def all_aliases
        aliases.pluck(:name)
      end

      def add_alias(text, kind: nil, confidence: 1.0)
        # Pre-validate before attempting to create
        return nil unless Validation::AliasFilter.valid?(text, canonical_name: name)

        aliases.find_or_create_by!(name: text) do |a|
          a.kind = kind
          a.confidence = confidence
        end
      rescue ActiveRecord::RecordInvalid
        # Alias validation failed (pronoun, generic term, etc.)
        nil
      end

      def matches_name?(query)
        return true if self.name.downcase == query.downcase

        aliases.exists?(["LOWER(name) = ?", query.downcase])
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
