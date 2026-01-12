# frozen_string_literal: true

class CreateFacts < ActiveRecord::Migration[7.0]
  def change
    create_table :fact_db_facts, comment: "Extracted factual assertions with temporal validity tracking (Event Clock pattern)" do |t|
      t.text :fact_text, null: false,
             comment: "The factual assertion in natural language form"
      t.string :fact_hash, null: false, limit: 64,
               comment: "SHA-256 hash of normalized fact_text for deduplication"

      t.timestamptz :valid_at, null: false,
                    comment: "When this fact became true (Event Clock valid_from)"
      t.timestamptz :invalid_at,
                    comment: "When this fact ceased to be true; NULL means still valid (Event Clock valid_to)"

      t.string :status, null: false, default: "canonical", limit: 20,
               comment: "Fact lifecycle state: canonical, superseded, retracted, or disputed"

      t.bigint :superseded_by_id,
               comment: "Reference to newer fact that replaces this one"
      t.bigint :derived_from_ids, array: true, default: [],
               comment: "Array of fact IDs from which this fact was inferred or derived"
      t.bigint :corroborated_by_ids, array: true, default: [],
               comment: "Array of fact IDs that independently confirm this fact"

      t.float :confidence, default: 1.0,
              comment: "Confidence score (0.0-1.0) in the accuracy of this fact"
      t.string :extraction_method, limit: 50,
               comment: "How fact was extracted: manual, llm_extraction, rule_based, etc."
      t.jsonb :metadata, null: false, default: {},
              comment: "Additional structured data: extraction context, source details, tags"

      t.vector :embedding, limit: 1536,
               comment: "Vector embedding for semantic fact search and similarity matching"

      t.timestamps
    end

    # Unique constraint on fact_hash + valid_at allows same fact text at different times
    add_index :fact_db_facts, [:fact_hash, :valid_at], unique: true, name: "index_fact_db_facts_on_fact_hash_valid_at"
    add_index :fact_db_facts, :valid_at
    add_index :fact_db_facts, :invalid_at
    add_index :fact_db_facts, :status
    add_index :fact_db_facts, :metadata, using: :gin
    add_foreign_key :fact_db_facts, :fact_db_facts,
                    column: :superseded_by_id, on_delete: :nullify

    # Compound index for temporal queries (the key Event Clock query pattern)
    execute <<-SQL
      CREATE INDEX idx_facts_temporal_validity ON fact_db_facts(valid_at, invalid_at)
      WHERE status = 'canonical';
    SQL

    # Partial index for currently valid facts
    execute <<-SQL
      CREATE INDEX idx_facts_currently_valid ON fact_db_facts(id)
      WHERE invalid_at IS NULL AND status = 'canonical';
    SQL

    # Full-text search index
    execute <<-SQL
      CREATE INDEX idx_facts_fulltext ON fact_db_facts
      USING gin(to_tsvector('english', fact_text));
    SQL

    # HNSW index for vector similarity search
    execute <<-SQL
      CREATE INDEX idx_facts_embedding ON fact_db_facts
      USING hnsw (embedding vector_cosine_ops);
    SQL

    # GIN trigram index on fact_text for fuzzy fact search
    execute <<-SQL
      CREATE INDEX idx_facts_text_trgm ON fact_db_facts
      USING gin (fact_text gin_trgm_ops);
    SQL

    execute "COMMENT ON COLUMN fact_db_facts.created_at IS 'When this fact was recorded in the database';"
    execute "COMMENT ON COLUMN fact_db_facts.updated_at IS 'When this fact record was last modified';"
  end
end
