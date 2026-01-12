# frozen_string_literal: true

module FactDb
  module Models
    class EntityAlias < ActiveRecord::Base
      self.table_name = "fact_db_entity_aliases"
      self.inheritance_column = nil # Disable STI - 'type' stores alias classification, not subclass

      belongs_to :entity, class_name: "FactDb::Models::Entity"

      validates :name, presence: true
      validates :name, uniqueness: { scope: :entity_id }
      validate :name_is_valid

      # Alias types
      TYPES = %w[name nickname email handle abbreviation title].freeze

      validates :type, inclusion: { in: TYPES }, allow_nil: true

      scope :by_type, ->(t) { where(type: t) }
      scope :high_confidence, -> { where("confidence >= ?", 0.9) }

      def self.find_entity_by_alias(text)
        find_by(["LOWER(name) = ?", text.downcase])&.entity
      end

      private

      def name_is_valid
        return if name.blank?

        entity_name = entity&.name
        unless Validation::AliasFilter.valid?(name, canonical_name: entity_name)
          reason = Validation::AliasFilter.rejection_reason(name, canonical_name: entity_name)
          errors.add(:name, "is not a valid alias: #{reason}")
        end
      end
    end
  end
end
