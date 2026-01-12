# frozen_string_literal: true

module FactDb
  module Models
    class FactSource < ActiveRecord::Base
      self.table_name = "fact_db_fact_sources"

      belongs_to :fact, class_name: "FactDb::Models::Fact"
      belongs_to :source, class_name: "FactDb::Models::Source"

      validates :fact_id, uniqueness: { scope: :source_id }

      # Source relationship kinds
      KINDS = %w[primary supporting corroborating].freeze

      validates :kind, inclusion: { in: KINDS }

      scope :primary, -> { where(kind: "primary") }
      scope :supporting, -> { where(kind: "supporting") }
      scope :corroborating, -> { where(kind: "corroborating") }
      scope :high_confidence, -> { where("confidence >= ?", 0.9) }

      def primary?
        kind == "primary"
      end

      def excerpt_preview(length: 100)
        return nil if excerpt.nil?
        return excerpt if excerpt.length <= length

        "#{excerpt[0, length]}..."
      end
    end
  end
end
