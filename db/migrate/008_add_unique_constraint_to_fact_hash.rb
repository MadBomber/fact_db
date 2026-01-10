# frozen_string_literal: true

class AddUniqueConstraintToFactHash < ActiveRecord::Migration[7.0]
  def up
    # Remove duplicates first - keep the earliest created record for each unique combination
    execute <<-SQL
      DELETE FROM fact_db_facts
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM fact_db_facts
        GROUP BY fact_hash, valid_at
      );
    SQL

    # Remove the old non-unique index
    remove_index :fact_db_facts, :fact_hash

    # Add unique constraint on fact_hash + valid_at
    # This allows the same fact text to be valid at different times
    add_index :fact_db_facts, [:fact_hash, :valid_at], unique: true, name: "index_fact_db_facts_on_fact_hash_valid_at"
  end

  def down
    remove_index :fact_db_facts, name: "index_fact_db_facts_on_fact_hash_valid_at"
    add_index :fact_db_facts, :fact_hash
  end
end
