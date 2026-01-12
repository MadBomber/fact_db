# frozen_string_literal: true

module FactDb
  module Models
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

      # Content kinds
      KINDS = %w[email transcript document slack meeting_notes contract report].freeze

      validates :kind, inclusion: { in: KINDS }, allow_nil: false

      scope :by_kind, ->(k) { where(kind: k) }
      scope :captured_between, ->(from, to) { where(captured_at: from..to) }
      scope :captured_after, ->(date) { where("captured_at >= ?", date) }
      scope :captured_before, ->(date) { where("captured_at <= ?", date) }

      # Full-text search
      scope :search_text, lambda { |query|
        where("to_tsvector('english', content) @@ plainto_tsquery('english', ?)", query)
      }

      # Vector similarity search (requires neighbor gem configured)
      def self.nearest_neighbors(embedding, limit: 10)
        return none unless embedding

        order(Arel.sql("embedding <=> '#{embedding}'")).limit(limit)
      end

      def immutable?
        true
      end

      def word_count
        content.split.size
      end

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
