# frozen_string_literal: true

module FactDb
  module Models
    class Fact < ActiveRecord::Base
      self.table_name = "fact_db_facts"

      has_many :entity_mentions, class_name: "FactDb::Models::EntityMention",
               foreign_key: :fact_id, dependent: :destroy
      has_many :entities, through: :entity_mentions

      has_many :fact_sources, class_name: "FactDb::Models::FactSource",
               foreign_key: :fact_id, dependent: :destroy
      has_many :sources, through: :fact_sources, source: :source

      belongs_to :superseded_by, class_name: "FactDb::Models::Fact",
                 foreign_key: :superseded_by_id, optional: true
      has_many :supersedes, class_name: "FactDb::Models::Fact",
               foreign_key: :superseded_by_id

      validates :fact_text, presence: true
      validates :fact_hash, presence: true, uniqueness: { scope: :valid_at }
      validates :valid_at, presence: true
      validates :status, presence: true

      before_validation :generate_fact_hash, on: :create

      # Fact statuses
      STATUSES = %w[canonical superseded corroborated synthesized].freeze
      EXTRACTION_METHODS = %w[manual llm rule_based].freeze

      validates :status, inclusion: { in: STATUSES }
      validates :extraction_method, inclusion: { in: EXTRACTION_METHODS }, allow_nil: true

      # Core scopes
      scope :canonical, -> { where(status: "canonical") }
      scope :superseded, -> { where(status: "superseded") }
      scope :synthesized, -> { where(status: "synthesized") }

      # Temporal scopes - the heart of the Event Clock
      scope :currently_valid, -> { where(invalid_at: nil) }
      scope :historical, -> { where.not(invalid_at: nil) }

      scope :valid_at, lambda { |date|
        where("valid_at <= ?", date)
          .where("invalid_at > ? OR invalid_at IS NULL", date)
      }

      scope :valid_between, lambda { |from, to|
        where("valid_at <= ? AND (invalid_at > ? OR invalid_at IS NULL)", to, from)
      }

      scope :became_valid_between, lambda { |from, to|
        where(valid_at: from..to)
      }

      scope :became_invalid_between, lambda { |from, to|
        where(invalid_at: from..to)
      }

      # Entity filtering
      scope :mentioning_entity, lambda { |entity_id|
        joins(:entity_mentions).where(fact_db_entity_mentions: { entity_id: entity_id }).distinct
      }

      scope :with_role, lambda { |entity_id, role|
        joins(:entity_mentions).where(
          fact_db_entity_mentions: { entity_id: entity_id, mention_role: role }
        ).distinct
      }

      # Full-text search
      scope :search_text, lambda { |query|
        where("to_tsvector('english', fact_text) @@ plainto_tsquery('english', ?)", query)
      }

      # Extraction method
      scope :extracted_by, ->(method) { where(extraction_method: method) }
      scope :by_extraction_method, ->(method) { where(extraction_method: method) }

      # Confidence filtering
      scope :high_confidence, -> { where("confidence >= ?", 0.9) }
      scope :low_confidence, -> { where("confidence < ?", 0.5) }

      def currently_valid?
        invalid_at.nil?
      end

      def valid_at?(date)
        valid_at <= date && (invalid_at.nil? || invalid_at > date)
      end

      def duration
        return nil if invalid_at.nil?

        invalid_at - valid_at
      end

      def duration_days
        return nil if invalid_at.nil?

        (invalid_at.to_date - valid_at.to_date).to_i
      end

      def superseded?
        status == "superseded"
      end

      def synthesized?
        status == "synthesized"
      end

      def invalidate!(at: Time.current)
        update!(invalid_at: at)
      end

      def supersede_with!(new_fact_text, valid_at:)
        transaction do
          new_fact = self.class.create!(
            fact_text: new_fact_text,
            valid_at: valid_at,
            status: "canonical",
            extraction_method: extraction_method
          )

          update!(
            status: "superseded",
            superseded_by_id: new_fact.id,
            invalid_at: valid_at
          )

          new_fact
        end
      end

      def add_mention(entity:, text:, role: nil, confidence: 1.0)
        entity_mentions.find_or_create_by!(entity: entity, mention_text: text) do |m|
          m.mention_role = role
          m.confidence = confidence
        end
      end

      def add_source(source:, type: "primary", excerpt: nil, confidence: 1.0)
        fact_sources.find_or_create_by!(source: source) do |s|
          s.source_type = type
          s.excerpt = excerpt
          s.confidence = confidence
        end
      end

      # Get source facts for synthesized facts
      def source_facts
        return Fact.none unless derived_from_ids.any?

        Fact.where(id: derived_from_ids)
      end

      # Get facts that corroborate this one
      def corroborating_facts
        return Fact.none unless corroborated_by_ids.any?

        Fact.where(id: corroborated_by_ids)
      end

      # Evidence chain - trace back to original sources
      def evidence_chain
        evidence = sources.to_a

        if synthesized? && derived_from_ids.any?
          source_facts.each do |source_fact|
            evidence.concat(source_fact.evidence_chain)
          end
        end

        evidence.uniq
      end

      # Returns the original source lines from which this fact was derived
      # Returns a hash with :full_section, :focused_lines, and :focused_line_numbers
      def prove_it
        source = fact_sources.first&.source
        return nil unless source&.content

        line_start = metadata&.dig("line_start")
        line_end = metadata&.dig("line_end")
        return nil unless line_start && line_end

        lines = source.content.lines
        start_idx = line_start.to_i - 1
        end_idx = line_end.to_i - 1

        return nil if start_idx < 0 || end_idx >= lines.length

        section_lines = lines[start_idx..end_idx]
        full_section = section_lines.join

        # Find focused lines by matching key terms from fact
        key_terms = extract_key_terms
        scored_lines = score_lines_by_relevance(section_lines, key_terms, start_idx)

        # Return lines that have at least one match, sorted by line number
        relevant = scored_lines.select { |l| l[:score] > 0 }
                               .sort_by { |l| l[:line_number] }

        {
          full_section: full_section,
          focused_lines: relevant.map { |l| l[:text] }.join,
          focused_line_numbers: relevant.map { |l| l[:line_number] },
          key_terms: key_terms
        }
      end

      private

      def extract_key_terms
        terms = []

        # Get entity names from mentions
        entity_mentions.includes(:entity).each do |mention|
          terms << mention.entity&.canonical_name if mention.entity&.canonical_name
          terms << mention.mention_text if mention.mention_text
        end

        # Extract significant words from fact text (exclude common words)
        stop_words = %w[a an the is was were are been being have has had do does did
                        will would could should may might must shall can to of in for
                        on with at by from as into through during before after above
                        below between under again further then once here there when
                        where why how all each few more most other some such no nor
                        not only own same so than too very just and but or if]

        fact_words = fact_text.downcase
                              .gsub(/[^a-z\s]/, " ")
                              .split
                              .reject { |w| w.length < 3 || stop_words.include?(w) }
                              .uniq

        terms.concat(fact_words)
        terms.compact.uniq.reject(&:empty?)
      end

      def score_lines_by_relevance(lines, key_terms, start_idx)
        lines.each_with_index.map do |line, idx|
          line_lower = line.downcase
          score = key_terms.count { |term| line_lower.include?(term.downcase) }

          {
            line_number: start_idx + idx + 1,
            text: line,
            score: score
          }
        end
      end

      public

      # Vector similarity search
      def self.nearest_neighbors(embedding, limit: 10)
        return none unless embedding

        order(Arel.sql("embedding <=> '#{embedding}'")).limit(limit)
      end

      private

      def generate_fact_hash
        self.fact_hash = Digest::SHA256.hexdigest(fact_text) if fact_text.present?
      end
    end
  end
end
