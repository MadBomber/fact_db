# frozen_string_literal: true

class CreateEntityAliases < ActiveRecord::Migration[7.0]
  def change
    create_table :fact_db_entity_aliases, comment: "Alternative names and identifiers for entities enabling flexible matching" do |t|
      t.references :entity, null: false, foreign_key: { to_table: :fact_db_entities, on_delete: :cascade },
                   comment: "The canonical entity this alias refers to"
      t.string :alias_text, null: false, limit: 500,
               comment: "The alternative name, identifier, or reference text"
      t.string :alias_type, limit: 50,
               comment: "Classification of alias: name, nickname, email, handle, abbreviation, former_name"
      t.float :confidence, default: 1.0,
              comment: "Confidence score (0.0-1.0) that this alias correctly refers to the entity"

      t.timestamps
    end

    add_index :fact_db_entity_aliases, :alias_text
    add_index :fact_db_entity_aliases, [:entity_id, :alias_text], unique: true,
              name: "idx_unique_entity_alias"

    # GIN trigram index on alias_text for fuzzy alias matching
    execute <<-SQL
      CREATE INDEX idx_entity_aliases_text_trgm ON fact_db_entity_aliases
      USING gin (alias_text gin_trgm_ops);
    SQL

    execute "COMMENT ON COLUMN fact_db_entity_aliases.created_at IS 'When this alias association was created';"
    execute "COMMENT ON COLUMN fact_db_entity_aliases.updated_at IS 'When this alias record was last modified';"
  end
end
