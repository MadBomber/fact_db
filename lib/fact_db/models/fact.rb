# frozen_string_literal: true

module FactDb
  module Models
    # Represents a temporal fact in the database
    #
    # Facts are the core data structure in FactDb, representing statements with
    # temporal validity (valid_at/invalid_at), entity mentions, and source provenance.
    # Facts can be canonical, superseded, or synthesized from other facts.
    #
    # @example Create a fact
    #   fact = Fact.create!(
    #     text: "John works at Acme Corp",
    #     valid_at: Date.parse("2024-01-15"),
    #     status: "canonical"
    #   )
    #
    # @example Query currently valid facts
    #   Fact.canonical.currently_valid
    #
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

      validates :text, presence: true
      validates :digest, presence: true, uniqueness: { scope: :valid_at }
      validates :valid_at, presence: true
      validates :status, presence: true

      before_validation :generate_digest, on: :create

      # @return [Array<String>] valid fact statuses
      STATUSES = %w[canonical superseded corroborated synthesized].freeze

      # @return [Array<String>] valid extraction methods
      EXTRACTION_METHODS = %w[manual llm rule_based].freeze

      validates :status, inclusion: { in: STATUSES }
      validates :extraction_method, inclusion: { in: EXTRACTION_METHODS }, allow_nil: true

      # @!group Scopes

      # @!method canonical
      #   Returns facts with canonical status
      #   @return [ActiveRecord::Relation]
      scope :canonical, -> { where(status: "canonical") }

      # @!method superseded
      #   Returns facts that have been superseded
      #   @return [ActiveRecord::Relation]
      scope :superseded, -> { where(status: "superseded") }

      # @!method synthesized
      #   Returns facts that were synthesized from other facts
      #   @return [ActiveRecord::Relation]
      scope :synthesized, -> { where(status: "synthesized") }

      # @!method currently_valid
      #   Returns facts that are currently valid (no invalid_at date)
      #   @return [ActiveRecord::Relation]
      scope :currently_valid, -> { where(invalid_at: nil) }

      # @!method historical
      #   Returns facts that have been invalidated
      #   @return [ActiveRecord::Relation]
      scope :historical, -> { where.not(invalid_at: nil) }

      # @!method valid_at(date)
      #   Returns facts valid at a specific point in time
      #   @param date [Date, Time] the point in time
      #   @return [ActiveRecord::Relation]
      scope :valid_at, lambda { |date|
        where("valid_at <= ?", date)
          .where("invalid_at > ? OR invalid_at IS NULL", date)
      }

      # @!method valid_between(from, to)
      #   Returns facts valid during a date range
      #   @param from [Date, Time] start of range
      #   @param to [Date, Time] end of range
      #   @return [ActiveRecord::Relation]
      scope :valid_between, lambda { |from, to|
        where("valid_at <= ? AND (invalid_at > ? OR invalid_at IS NULL)", to, from)
      }

      # @!method became_valid_between(from, to)
      #   Returns facts that became valid within a date range
      #   @param from [Date, Time] start of range
      #   @param to [Date, Time] end of range
      #   @return [ActiveRecord::Relation]
      scope :became_valid_between, lambda { |from, to|
        where(valid_at: from..to)
      }

      # @!method became_invalid_between(from, to)
      #   Returns facts that became invalid within a date range
      #   @param from [Date, Time] start of range
      #   @param to [Date, Time] end of range
      #   @return [ActiveRecord::Relation]
      scope :became_invalid_between, lambda { |from, to|
        where(invalid_at: from..to)
      }

      # @!method mentioning_entity(entity_id)
      #   Returns facts that mention a specific entity
      #   @param entity_id [Integer] the entity ID
      #   @return [ActiveRecord::Relation]
      scope :mentioning_entity, lambda { |entity_id|
        joins(:entity_mentions).where(fact_db_entity_mentions: { entity_id: entity_id }).distinct
      }

      # @!method with_role(entity_id, role)
      #   Returns facts where an entity has a specific role
      #   @param entity_id [Integer] the entity ID
      #   @param role [String, Symbol] the mention role (subject, object, etc.)
      #   @return [ActiveRecord::Relation]
      scope :with_role, lambda { |entity_id, role|
        joins(:entity_mentions).where(
          fact_db_entity_mentions: { entity_id: entity_id, mention_role: role }
        ).distinct
      }

      # @!method search_text(query)
      #   Full-text search on fact text using PostgreSQL tsvector
      #   @param query [String] the search query
      #   @return [ActiveRecord::Relation]
      scope :search_text, lambda { |query|
        where("to_tsvector('english', text) @@ plainto_tsquery('english', ?)", query)
      }

      # @!method extracted_by(method)
      #   Returns facts extracted by a specific method
      #   @param method [String, Symbol] extraction method (manual, llm, rule_based)
      #   @return [ActiveRecord::Relation]
      scope :extracted_by, ->(method) { where(extraction_method: method) }

      # @!method by_extraction_method(method)
      #   Alias for extracted_by
      #   @param method [String, Symbol] extraction method
      #   @return [ActiveRecord::Relation]
      scope :by_extraction_method, ->(method) { where(extraction_method: method) }

      # @!method high_confidence
      #   Returns facts with confidence >= 0.9
      #   @return [ActiveRecord::Relation]
      scope :high_confidence, -> { where("confidence >= ?", 0.9) }

      # @!method low_confidence
      #   Returns facts with confidence < 0.5
      #   @return [ActiveRecord::Relation]
      scope :low_confidence, -> { where("confidence < ?", 0.5) }

      # @!endgroup

      # Checks if the fact is currently valid
      #
      # @return [Boolean] true if the fact has no invalid_at date
      def currently_valid?
        invalid_at.nil?
      end

      # Checks if the fact was valid at a specific date
      #
      # @param date [Date, Time] the point in time to check
      # @return [Boolean] true if the fact was valid at the given date
      def valid_at?(date)
        valid_at <= date && (invalid_at.nil? || invalid_at > date)
      end

      # Returns the duration the fact was valid
      #
      # @return [ActiveSupport::Duration, nil] duration or nil if still valid
      def duration
        return nil if invalid_at.nil?

        invalid_at - valid_at
      end

      # Returns the duration in days the fact was valid
      #
      # @return [Integer, nil] number of days or nil if still valid
      def duration_days
        return nil if invalid_at.nil?

        (invalid_at.to_date - valid_at.to_date).to_i
      end

      # Checks if this fact has been superseded
      #
      # @return [Boolean] true if status is "superseded"
      def superseded?
        status == "superseded"
      end

      # Checks if this fact was synthesized from other facts
      #
      # @return [Boolean] true if status is "synthesized"
      def synthesized?
        status == "synthesized"
      end

      # Invalidates this fact at a specific time
      #
      # @param at [Time] when the fact became invalid (defaults to now)
      # @return [Boolean] true if update succeeded
      def invalidate!(at: Time.current)
        update!(invalid_at: at)
      end

      # Supersedes this fact with new information
      #
      # Creates a new canonical fact and marks this one as superseded.
      #
      # @param new_text [String] the updated fact text
      # @param valid_at [Date, Time] when the new fact became valid
      # @return [FactDb::Models::Fact] the new fact
      def supersede_with!(new_text, valid_at:)
        transaction do
          new_fact = self.class.create!(
            text: new_text,
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

      # Adds an entity mention to this fact
      #
      # @param entity [FactDb::Models::Entity] the entity being mentioned
      # @param text [String] the mention text as it appears in the fact
      # @param role [String, Symbol, nil] the role (subject, object, etc.)
      # @param confidence [Float] confidence score (0.0 to 1.0)
      # @return [FactDb::Models::EntityMention] the created or found mention
      def add_mention(entity:, text:, role: nil, confidence: 1.0)
        entity_mentions.find_or_create_by!(entity: entity, mention_text: text) do |m|
          m.mention_role = role
          m.confidence = confidence
        end
      end

      # Adds a source document to this fact
      #
      # @param source [FactDb::Models::Source] the source document
      # @param kind [String] source kind (primary, corroborating, etc.)
      # @param excerpt [String, nil] relevant excerpt from the source
      # @param confidence [Float] confidence score (0.0 to 1.0)
      # @return [FactDb::Models::FactSource] the created or found fact-source link
      def add_source(source:, kind: "primary", excerpt: nil, confidence: 1.0)
        fact_sources.find_or_create_by!(source: source) do |s|
          s.kind = kind
          s.excerpt = excerpt
          s.confidence = confidence
        end
      end

      # Returns the source facts for synthesized facts
      #
      # @return [ActiveRecord::Relation] facts this one was derived from
      def source_facts
        return Fact.none unless derived_from_ids.any?

        Fact.where(id: derived_from_ids)
      end

      # Returns facts that corroborate this one
      #
      # @return [ActiveRecord::Relation] corroborating facts
      def corroborating_facts
        return Fact.none unless corroborated_by_ids.any?

        Fact.where(id: corroborated_by_ids)
      end

      # Returns the complete evidence chain back to original sources
      #
      # Recursively traces through synthesized facts to find all original sources.
      #
      # @return [Array<FactDb::Models::Source>] unique source documents
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
      #
      # Uses line metadata to extract the relevant section from the source document
      # and highlights lines containing key terms from the fact.
      #
      # @return [Hash, nil] hash with :full_section, :focused_lines, :focused_line_numbers, :key_terms
      #   or nil if source/line metadata unavailable
      #
      # @example
      #   fact.prove_it
      #   # => {
      #   #   full_section: "...",
      #   #   focused_lines: "John joined Acme Corp...",
      #   #   focused_line_numbers: [15, 16],
      #   #   key_terms: ["John", "Acme Corp"]
      #   # }
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
          terms << mention.entity&.name if mention.entity&.name
          terms << mention.mention_text if mention.mention_text
        end

        # Extract significant words from fact text (exclude common words)
        stop_words = %w[a an the is was were are been being have has had do does did
                        will would could should may might must shall can to of in for
                        on with at by from as into through during before after above
                        below between under again further then once here there when
                        where why how all each few more most other some such no nor
                        not only own same so than too very just and but or if]

        fact_words = text.downcase
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

      # Finds facts by vector similarity using pgvector
      #
      # @param embedding [Array<Float>] the embedding vector to search with
      # @param limit [Integer] maximum number of results
      # @return [ActiveRecord::Relation] facts ordered by similarity
      def self.nearest_neighbors(embedding, limit: 10)
        return none unless embedding

        order(Arel.sql("embedding <=> '#{embedding}'")).limit(limit)
      end

      private

      def generate_digest
        self.digest = Digest::SHA256.hexdigest(text) if text.present?
      end
    end
  end
end
