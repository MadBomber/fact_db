# frozen_string_literal: true

class AddTrigramSearchSupport < ActiveRecord::Migration[7.0]
  def up
    # Enable pg_trgm extension for fuzzy/similarity search
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    # GIN trigram index on entity canonical_name for fast fuzzy matching
    # Supports: similarity(), %, <->  operators
    execute <<-SQL
      CREATE INDEX idx_entities_canonical_name_trgm ON fact_db_entities
      USING gin (canonical_name gin_trgm_ops);
    SQL

    # GIN trigram index on entity aliases for fuzzy alias matching
    execute <<-SQL
      CREATE INDEX idx_entity_aliases_text_trgm ON fact_db_entity_aliases
      USING gin (alias_text gin_trgm_ops);
    SQL

    # GIN trigram index on fact_text for fuzzy fact search
    # Complements the existing full-text search index
    execute <<-SQL
      CREATE INDEX idx_facts_text_trgm ON fact_db_facts
      USING gin (fact_text gin_trgm_ops);
    SQL

    # Set default similarity threshold (can be adjusted per-session)
    # Default is 0.3, we set slightly lower to catch more misspellings
    execute "SET pg_trgm.similarity_threshold = 0.25;"
  end

  def down
    execute "DROP INDEX IF EXISTS idx_entities_canonical_name_trgm;"
    execute "DROP INDEX IF EXISTS idx_entity_aliases_text_trgm;"
    execute "DROP INDEX IF EXISTS idx_facts_text_trgm;"
    disable_extension "pg_trgm"
  end
end
