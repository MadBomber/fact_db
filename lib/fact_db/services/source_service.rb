# frozen_string_literal: true

module FactDb
  module Services
    class SourceService
      attr_reader :config

      def initialize(config = FactDb.config)
        @config = config
      end

      def create(content, type:, captured_at: Time.current, metadata: {}, title: nil, source_uri: nil)
        content_hash = Digest::SHA256.hexdigest(content)

        # Check for duplicate content
        existing = Models::Source.find_by(content_hash: content_hash)
        return existing if existing

        embedding = generate_embedding(content)

        Models::Source.create!(
          content: content,
          content_hash: content_hash,
          type: type.to_s,
          title: title,
          source_uri: source_uri,
          source_metadata: metadata,
          captured_at: captured_at,
          embedding: embedding
        )
      end

      def find(id)
        Models::Source.find(id)
      end

      def find_by_hash(hash)
        Models::Source.find_by(content_hash: hash)
      end

      def search(query, type: nil, from: nil, to: nil, limit: 20)
        scope = Models::Source.search_text(query)
        scope = scope.by_type(type) if type
        scope = scope.captured_after(from) if from
        scope = scope.captured_before(to) if to
        scope.order(captured_at: :desc).limit(limit)
      end

      def semantic_search(query, limit: 20)
        embedding = generate_embedding(query)
        return Models::Source.none unless embedding

        Models::Source.nearest_neighbors(embedding, limit: limit)
      end

      def by_type(type, limit: nil)
        scope = Models::Source.by_type(type).order(captured_at: :desc)
        scope = scope.limit(limit) if limit
        scope
      end

      def between(from, to)
        Models::Source.captured_between(from, to).order(captured_at: :asc)
      end

      def recent(limit: 10)
        Models::Source.order(captured_at: :desc).limit(limit)
      end

      def stats
        {
          total: Models::Source.count,
          total_count: Models::Source.count,
          by_type: Models::Source.group(:type).count,
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
