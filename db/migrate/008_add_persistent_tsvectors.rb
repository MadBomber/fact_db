# frozen_string_literal: true

class AddPersistentTsvectors < ActiveRecord::Migration[7.0]
  # Uses disable_ddl_transaction! so GIN indexes can be created CONCURRENTLY
  # without holding an exclusive lock on the table.
  disable_ddl_transaction!

  def up
    # --- fact_db_facts: persist tsvector for full-text search on text column ---

    add_column :fact_db_facts, :text_vector, :tsvector,
               comment: "Precomputed tsvector for full-text search on text"

    execute <<-SQL
      CREATE TRIGGER fact_db_facts_text_vector_update
        BEFORE INSERT OR UPDATE ON fact_db_facts
        FOR EACH ROW
        EXECUTE FUNCTION tsvector_update_trigger(
          text_vector,
          'pg_catalog.english',
          text
        );
    SQL

    execute <<-SQL
      CREATE INDEX CONCURRENTLY idx_facts_text_vector
        ON fact_db_facts
        USING GIN (text_vector);
    SQL

    # Backfill existing rows by touching them so the trigger fires
    execute <<-SQL
      UPDATE fact_db_facts SET text_vector = to_tsvector('english', COALESCE(text, ''));
    SQL

    # --- fact_db_sources: persist tsvector for full-text search on content column ---

    add_column :fact_db_sources, :content_vector, :tsvector,
               comment: "Precomputed tsvector for full-text search on content"

    execute <<-SQL
      CREATE TRIGGER fact_db_sources_content_vector_update
        BEFORE INSERT OR UPDATE ON fact_db_sources
        FOR EACH ROW
        EXECUTE FUNCTION tsvector_update_trigger(
          content_vector,
          'pg_catalog.english',
          content
        );
    SQL

    execute <<-SQL
      CREATE INDEX CONCURRENTLY idx_sources_content_vector
        ON fact_db_sources
        USING GIN (content_vector);
    SQL

    # Backfill existing rows
    execute <<-SQL
      UPDATE fact_db_sources SET content_vector = to_tsvector('english', COALESCE(content, ''));
    SQL

    # Drop the old expression-based GIN indexes (now redundant)
    execute "DROP INDEX IF EXISTS idx_facts_fulltext;"
    execute "DROP INDEX IF EXISTS idx_sources_fulltext;"
  end

  def down
    # Restore the original expression-based GIN indexes
    execute <<-SQL
      CREATE INDEX CONCURRENTLY idx_facts_fulltext ON fact_db_facts
        USING gin(to_tsvector('english', text));
    SQL

    execute <<-SQL
      CREATE INDEX CONCURRENTLY idx_sources_fulltext ON fact_db_sources
        USING gin(to_tsvector('english', content));
    SQL

    # Drop triggers
    execute <<-SQL
      DROP TRIGGER IF EXISTS fact_db_facts_text_vector_update ON fact_db_facts;
    SQL

    execute <<-SQL
      DROP TRIGGER IF EXISTS fact_db_sources_content_vector_update ON fact_db_sources;
    SQL

    # Drop indexes
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_facts_text_vector;"
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_sources_content_vector;"

    # Remove columns
    remove_column :fact_db_facts, :text_vector
    remove_column :fact_db_sources, :content_vector
  end
end
