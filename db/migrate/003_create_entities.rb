# frozen_string_literal: true

class CreateEntities < ActiveRecord::Migration[7.0]
  def change
    create_table :fact_db_entities, comment: "Canonical representations of people, organizations, places, and other named entities" do |t|
      t.string :canonical_name, null: false, limit: 500,
               comment: "Authoritative name for this entity after resolution and normalization"
      t.string :entity_type, null: false, limit: 50,
               comment: "Classification of entity (person, organization, location, product, event, etc.)"

      t.string :resolution_status, null: false, default: "unresolved", limit: 20,
               comment: "Entity resolution state: unresolved, resolved, merged, or ambiguous"
      t.bigint :merged_into_id,
               comment: "Reference to canonical entity if this entity was merged as a duplicate"

      t.text :description,
             comment: "Human-readable description providing context about this entity"
      t.jsonb :metadata, null: false, default: {},
              comment: "Flexible attributes specific to entity type (titles, roles, identifiers, etc.)"

      t.vector :embedding, limit: 1536,
               comment: "Vector embedding for semantic entity matching and similarity search"

      t.timestamps
    end

    add_index :fact_db_entities, :canonical_name
    add_index :fact_db_entities, :entity_type
    add_index :fact_db_entities, :resolution_status
    add_foreign_key :fact_db_entities, :fact_db_entities,
                    column: :merged_into_id, on_delete: :nullify

    # HNSW index for vector similarity search
    execute <<-SQL
      CREATE INDEX idx_entities_embedding ON fact_db_entities
      USING hnsw (embedding vector_cosine_ops);
    SQL

    # GIN trigram index on canonical_name for fast fuzzy matching
    execute <<-SQL
      CREATE INDEX idx_entities_canonical_name_trgm ON fact_db_entities
      USING gin (canonical_name gin_trgm_ops);
    SQL

    execute "COMMENT ON COLUMN fact_db_entities.created_at IS 'When this entity was first identified';"
    execute "COMMENT ON COLUMN fact_db_entities.updated_at IS 'When this entity record was last modified';"
  end
end
