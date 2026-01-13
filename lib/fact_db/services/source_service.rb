# frozen_string_literal: true

module FactDb
  module Services
    # Service class for managing source documents in the database
    #
    # Provides methods for creating, searching, and retrieving source documents
    # which are the original content from which facts are extracted.
    #
    # @example Basic usage
    #   service = SourceService.new
    #   source = service.create("Meeting notes...", kind: :document)
    #
    class SourceService
      # @return [FactDb::Config] the configuration object
      attr_reader :config

      # Initializes a new SourceService instance
      #
      # @param config [FactDb::Config] configuration object (defaults to FactDb.config)
      def initialize(config = FactDb.config)
        @config = config
      end

      # Creates a new source document in the database
      #
      # Automatically deduplicates by content hash - returns existing source if content matches.
      #
      # @param content [String] the source content text
      # @param kind [Symbol, String] source kind (:document, :email, :transcript, etc.)
      # @param captured_at [Time] when the source was captured (defaults to now)
      # @param metadata [Hash] additional metadata
      # @param title [String, nil] optional title
      # @param source_uri [String, nil] optional URI of the original source
      # @return [FactDb::Models::Source] the created or existing source
      #
      # @example Create a source with metadata
      #   service.create("Email content...",
      #     kind: :email,
      #     captured_at: Time.parse("2024-01-15"),
      #     metadata: { from: "john@example.com" })
      def create(content, kind:, captured_at: Time.current, metadata: {}, title: nil, source_uri: nil)
        content_hash = Digest::SHA256.hexdigest(content)

        # Check for duplicate content
        existing = Models::Source.find_by(content_hash: content_hash)
        return existing if existing

        embedding = generate_embedding(content)

        Models::Source.create!(
          content: content,
          content_hash: content_hash,
          kind: kind.to_s,
          title: title,
          source_uri: source_uri,
          metadata: metadata,
          captured_at: captured_at,
          embedding: embedding
        )
      end

      # Finds a source by ID
      #
      # @param id [Integer] the source ID
      # @return [FactDb::Models::Source] the found source
      # @raise [ActiveRecord::RecordNotFound] if source not found
      def find(id)
        Models::Source.find(id)
      end

      # Finds a source by content hash
      #
      # @param hash [String] the SHA256 content hash
      # @return [FactDb::Models::Source, nil] the found source or nil
      def find_by_hash(hash)
        Models::Source.find_by(content_hash: hash)
      end

      # Searches sources using full-text search with optional filters
      #
      # @param query [String] the search query
      # @param kind [Symbol, String, nil] optional kind filter
      # @param from [Date, Time, nil] captured after this date
      # @param to [Date, Time, nil] captured before this date
      # @param limit [Integer] maximum number of results
      # @return [ActiveRecord::Relation] matching sources
      def search(query, kind: nil, from: nil, to: nil, limit: 20)
        scope = Models::Source.search_text(query)
        scope = scope.by_kind(kind) if kind
        scope = scope.captured_after(from) if from
        scope = scope.captured_before(to) if to
        scope.order(captured_at: :desc).limit(limit)
      end

      # Searches sources using semantic similarity (vector search)
      #
      # Requires an embedding generator to be configured.
      #
      # @param query [String] the search query
      # @param limit [Integer] maximum number of results
      # @return [ActiveRecord::Relation] semantically similar sources
      def semantic_search(query, limit: 20)
        embedding = generate_embedding(query)
        return Models::Source.none unless embedding

        Models::Source.nearest_neighbors(embedding, limit: limit)
      end

      # Returns sources of a specific kind
      #
      # @param kind [Symbol, String] the source kind
      # @param limit [Integer, nil] maximum number of results
      # @return [ActiveRecord::Relation] sources of that kind
      def by_kind(kind, limit: nil)
        scope = Models::Source.by_kind(kind).order(captured_at: :desc)
        scope = scope.limit(limit) if limit
        scope
      end

      # Returns sources captured between two dates
      #
      # @param from [Date, Time] start of range
      # @param to [Date, Time] end of range
      # @return [ActiveRecord::Relation] sources in the date range
      def between(from, to)
        Models::Source.captured_between(from, to).order(captured_at: :asc)
      end

      # Returns recently captured sources
      #
      # @param limit [Integer] maximum number of results
      # @return [ActiveRecord::Relation] recent sources ordered by capture date
      def recent(limit: 10)
        Models::Source.order(captured_at: :desc).limit(limit)
      end

      # Returns aggregate statistics about sources
      #
      # @return [Hash] statistics including counts by kind and date range
      def stats
        {
          total: Models::Source.count,
          total_count: Models::Source.count,
          by_kind: Models::Source.group(:kind).count,
          earliest: Models::Source.minimum(:captured_at),
          latest: Models::Source.maximum(:captured_at),
          total_words: Models::Source.sum("array_length(regexp_split_to_array(content, '\\s+'), 1)")
        }
      end

      private

      def generate_embedding(text)
        return nil unless config.embedding_generator

        config.embedding_generator.call(text)
      rescue StandardError => e
        config.logger&.warn("Failed to generate embedding: #{e.message}")
        nil
      end
    end
  end
end
