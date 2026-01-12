# frozen_string_literal: true

class CreateEntityMentions < ActiveRecord::Migration[7.0]
  def change
    create_table :fact_db_entity_mentions, comment: "Links entities to facts where they are mentioned, with role context" do |t|
      t.references :fact, null: false, foreign_key: { to_table: :fact_db_facts, on_delete: :cascade },
                   comment: "The fact containing this entity mention"
      t.references :entity, null: false, foreign_key: { to_table: :fact_db_entities, on_delete: :cascade },
                   comment: "The resolved entity being mentioned"
      t.string :mention_text, null: false, limit: 500,
               comment: "The exact text used to reference the entity in the fact"
      t.string :mention_role, limit: 50,
               comment: "Semantic role of entity in fact: subject, object, location, time, instrument, etc."
      t.float :confidence, default: 1.0,
              comment: "Confidence score (0.0-1.0) that mention correctly resolves to entity"

      t.timestamps
    end

    add_index :fact_db_entity_mentions, [:fact_id, :entity_id, :mention_text],
              unique: true, name: "idx_unique_fact_entity_mention"

    execute "COMMENT ON COLUMN fact_db_entity_mentions.created_at IS 'When this mention link was created';"
    execute "COMMENT ON COLUMN fact_db_entity_mentions.updated_at IS 'When this mention record was last modified';"
  end
end
