# frozen_string_literal: true

class CreateFactSources < ActiveRecord::Migration[7.0]
  def change
    create_table :fact_db_fact_sources, comment: "Links facts to their source content for provenance tracking" do |t|
      t.references :fact, null: false, foreign_key: { to_table: :fact_db_facts, on_delete: :cascade },
                   comment: "The fact derived from this source"
      t.references :source, null: false, foreign_key: { to_table: :fact_db_sources, on_delete: :cascade },
                   comment: "The source content from which the fact was extracted"
      t.string :kind, default: "primary", limit: 50,
               comment: "Relationship type: primary (direct extraction), supporting, or corroborating"
      t.text :excerpt,
             comment: "The specific text passage within the content that supports this fact"
      t.float :confidence, default: 1.0,
              comment: "Confidence score (0.0-1.0) that this source supports the fact"

      t.timestamps
    end

    add_index :fact_db_fact_sources, [:fact_id, :source_id], unique: true,
              name: "idx_unique_fact_source"

    execute "COMMENT ON COLUMN fact_db_fact_sources.created_at IS 'When this source link was established';"
    execute "COMMENT ON COLUMN fact_db_fact_sources.updated_at IS 'When this source record was last modified';"
  end
end
