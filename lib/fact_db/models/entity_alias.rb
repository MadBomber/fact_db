# frozen_string_literal: true

module FactDb
  module Models
    # Represents an alternative name for an entity
    #
    # Aliases allow entities to be found by various name forms (nicknames,
    # abbreviations, email handles, etc.). Validation prevents invalid aliases
    # like pronouns or generic terms.
    #
    # @example Create an alias
    #   alias = EntityAlias.create!(entity: person, name: "Johnny", kind: "nickname")
    #
    class EntityAlias < ActiveRecord::Base
      self.table_name = "fact_db_entity_aliases"

      belongs_to :entity, class_name: "FactDb::Models::Entity"

      validates :name, presence: true
      validates :name, uniqueness: { scope: :entity_id }
      validate :name_is_valid

      # @return [Array<String>] valid alias kinds
      KINDS = %w[name nickname email handle abbreviation title].freeze

      validates :kind, inclusion: { in: KINDS }, allow_nil: true

      # @!method by_kind(k)
      #   Returns aliases of a specific kind
      #   @param k [String] the alias kind
      #   @return [ActiveRecord::Relation]
      scope :by_kind, ->(k) { where(kind: k) }

      # @!method high_confidence
      #   Returns aliases with confidence >= 0.9
      #   @return [ActiveRecord::Relation]
      scope :high_confidence, -> { where("confidence >= ?", 0.9) }

      # Finds an entity by alias text (case-insensitive)
      #
      # @param text [String] the alias text to search for
      # @return [Entity, nil] the entity with this alias or nil
      def self.find_entity_by_alias(text)
        find_by(["LOWER(name) = ?", text.downcase])&.entity
      end

      private

      def name_is_valid
        return if name.blank?

        entity_name = entity&.name
        unless Validation::AliasFilter.valid?(name, name: entity_name)
          reason = Validation::AliasFilter.rejection_reason(name, name: entity_name)
          errors.add(:name, "is not a valid alias: #{reason}")
        end
      end
    end
  end
end
