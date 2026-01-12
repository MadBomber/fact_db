# frozen_string_literal: true

class CreateSources < ActiveRecord::Migration[7.0]
  def change
    create_table :fact_db_sources, comment: "Stores immutable source content from which facts are extracted" do |t|
      t.string :content_hash, null: false, limit: 64,
               comment: "SHA-256 hash of content for deduplication and integrity verification"
      t.string :type, null: false, limit: 50,
               comment: "Classification of content origin (e.g., email, document, webpage, transcript)"

      t.text :content, null: false,
             comment: "Original unmodified text content, preserved for audit and re-extraction"
      t.string :title, limit: 500,
               comment: "Human-readable title or subject line of the content"

      t.text :source_uri,
             comment: "URI identifying the original source location (URL, file path, message ID)"
      t.jsonb :source_metadata, null: false, default: {},
              comment: "Flexible metadata about the source (author, date, headers, etc.)"

      t.vector :embedding, limit: 1536,
               comment: "Vector embedding for semantic similarity search (OpenAI ada-002 compatible)"

      t.timestamptz :captured_at, null: false,
                    comment: "When the content was originally captured or received"
      t.timestamps
    end

    add_index :fact_db_sources, :content_hash, unique: true
    add_index :fact_db_sources, :captured_at
    add_index :fact_db_sources, :type
    add_index :fact_db_sources, :source_metadata, using: :gin

    # Full-text search index
    execute <<-SQL
      CREATE INDEX idx_sources_fulltext ON fact_db_sources
      USING gin(to_tsvector('english', content));
    SQL

    # HNSW index for vector similarity search
    execute <<-SQL
      CREATE INDEX idx_sources_embedding ON fact_db_sources
      USING hnsw (embedding vector_cosine_ops);
    SQL

    execute "COMMENT ON COLUMN fact_db_sources.created_at IS 'When this record was created in the database';"
    execute "COMMENT ON COLUMN fact_db_sources.updated_at IS 'When this record was last modified';"
  end
end
