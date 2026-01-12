# frozen_string_literal: true

class CreateContents < ActiveRecord::Migration[7.0]
  def change
    create_table :fact_db_contents, comment: "Stores immutable source content from which facts are extracted" do |t|
      t.string :content_hash, null: false, limit: 64,
               comment: "SHA-256 hash of raw_text for deduplication and integrity verification"
      t.string :content_type, null: false, limit: 50,
               comment: "Classification of content origin (e.g., email, document, webpage, transcript)"

      t.text :raw_text, null: false,
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

    add_index :fact_db_contents, :content_hash, unique: true
    add_index :fact_db_contents, :captured_at
    add_index :fact_db_contents, :content_type
    add_index :fact_db_contents, :source_metadata, using: :gin

    # Full-text search index
    execute <<-SQL
      CREATE INDEX idx_contents_fulltext ON fact_db_contents
      USING gin(to_tsvector('english', raw_text));
    SQL

    # HNSW index for vector similarity search
    execute <<-SQL
      CREATE INDEX idx_contents_embedding ON fact_db_contents
      USING hnsw (embedding vector_cosine_ops);
    SQL

    execute "COMMENT ON COLUMN fact_db_contents.created_at IS 'When this record was created in the database';"
    execute "COMMENT ON COLUMN fact_db_contents.updated_at IS 'When this record was last modified';"
  end
end
