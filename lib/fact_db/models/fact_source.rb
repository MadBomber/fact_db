# frozen_string_literal: true

module FactDb
  module Models
    # Join model linking facts to source documents
    #
    # Represents the provenance relationship between a fact and the source
    # document(s) it was extracted from, including the relationship type
    # and an optional excerpt.
    #
    # @example Link a fact to a source
    #   fact_source = FactSource.create!(
    #     fact: fact, source: document,
    #     kind: "primary", excerpt: "relevant quote..."
    #   )
    #
    class FactSource < ActiveRecord::Base
      self.table_name = "fact_db_fact_sources"

      belongs_to :fact, class_name: "FactDb::Models::Fact"
      belongs_to :source, class_name: "FactDb::Models::Source"

      validates :fact_id, uniqueness: { scope: :source_id }

      # @return [Array<String>] valid source relationship kinds
      KINDS = %w[primary supporting corroborating].freeze

      validates :kind, inclusion: { in: KINDS }

      # @!method primary
      #   Returns primary source links
      #   @return [ActiveRecord::Relation]
      scope :primary, -> { where(kind: "primary") }

      # @!method supporting
      #   Returns supporting source links
      #   @return [ActiveRecord::Relation]
      scope :supporting, -> { where(kind: "supporting") }

      # @!method corroborating
      #   Returns corroborating source links
      #   @return [ActiveRecord::Relation]
      scope :corroborating, -> { where(kind: "corroborating") }

      # @!method high_confidence
      #   Returns source links with confidence >= 0.9
      #   @return [ActiveRecord::Relation]
      scope :high_confidence, -> { where("confidence >= ?", 0.9) }

      # Checks if this is the primary source for the fact
      #
      # @return [Boolean] true if kind is "primary"
      def primary?
        kind == "primary"
      end

      # Returns a preview of the excerpt, truncated if needed
      #
      # @param length [Integer] maximum length (default: 100)
      # @return [String, nil] excerpt preview with "..." if truncated, or nil if no excerpt
      def excerpt_preview(length: 100)
        return nil if excerpt.nil?
        return excerpt if excerpt.length <= length

        "#{excerpt[0, length]}..."
      end
    end
  end
end
