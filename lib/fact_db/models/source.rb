# frozen_string_literal: true

module FactDb
  module Models
    # Represents a source document from which facts are extracted
    #
    # Sources are immutable content documents (emails, transcripts, documents, etc.)
    # that serve as the provenance for extracted facts. Content is deduplicated
    # by SHA256 hash.
    #
    # @example Create a source
    #   source = Source.create!(content: "Meeting notes...", kind: "meeting_notes", captured_at: Time.now)
    #
    # @example Search sources
    #   Source.search_text("quarterly report").by_kind("document")
    #
    class Source < ActiveRecord::Base
      self.table_name = "fact_db_sources"

      has_many :fact_sources, class_name: "FactDb::Models::FactSource",
               foreign_key: :source_id, dependent: :destroy
      has_many :facts, through: :fact_sources

      validates :content_hash, presence: true, uniqueness: true
      validates :kind, presence: true
      validates :content, presence: true
      validates :captured_at, presence: true

      before_validation :generate_content_hash, on: :create

      # @return [Array<String>] valid source content kinds
      KINDS = %w[email transcript document slack meeting_notes contract report].freeze

      validates :kind, inclusion: { in: KINDS }, allow_nil: false

      # @!method by_kind(k)
      #   Returns sources of a specific kind
      #   @param k [String] the source kind
      #   @return [ActiveRecord::Relation]
      scope :by_kind, ->(k) { where(kind: k) }

      # @!method captured_between(from, to)
      #   Returns sources captured within a date range
      #   @param from [Date, Time] start of range
      #   @param to [Date, Time] end of range
      #   @return [ActiveRecord::Relation]
      scope :captured_between, ->(from, to) { where(captured_at: from..to) }

      # @!method captured_after(date)
      #   Returns sources captured after a date
      #   @param date [Date, Time] the cutoff date
      #   @return [ActiveRecord::Relation]
      scope :captured_after, ->(date) { where("captured_at >= ?", date) }

      # @!method captured_before(date)
      #   Returns sources captured before a date
      #   @param date [Date, Time] the cutoff date
      #   @return [ActiveRecord::Relation]
      scope :captured_before, ->(date) { where("captured_at <= ?", date) }

      # @!method search_text(query)
      #   Full-text search on source content using PostgreSQL tsvector
      #   @param query [String] the search query
      #   @return [ActiveRecord::Relation]
      scope :search_text, lambda { |query|
        where("to_tsvector('english', content) @@ plainto_tsquery('english', ?)", query)
      }

      # Finds sources by vector similarity using pgvector
      #
      # @param embedding [Array<Float>] the embedding vector to search with
      # @param limit [Integer] maximum number of results
      # @return [ActiveRecord::Relation] sources ordered by similarity
      def self.nearest_neighbors(embedding, limit: 10)
        return none unless embedding

        order(Arel.sql("embedding <=> '#{embedding}'")).limit(limit)
      end

      # Returns whether the source content can be modified
      #
      # Sources are always immutable to preserve provenance integrity.
      #
      # @return [Boolean] always returns true
      def immutable?
        true
      end

      # Returns the word count of the content
      #
      # @return [Integer] number of words in content
      def word_count
        content.split.size
      end

      # Returns a preview of the content, truncated if needed
      #
      # @param length [Integer] maximum length (default: 200)
      # @return [String] content preview with "..." if truncated
      def preview(length: 200)
        return content if content.length <= length

        "#{content[0, length]}..."
      end

      private

      def generate_content_hash
        self.content_hash = Digest::SHA256.hexdigest(content) if content.present?
      end
    end
  end
end
