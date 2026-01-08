# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "fact_db"

# Configure for testing
FactDb.configure do |config|
  config.database_url = ENV.fetch("DATABASE_URL", "postgresql://dewayne@localhost/fact_db_test")
  config.logger = Logger.new(File::NULL) # Silence logs in tests
  config.fuzzy_match_threshold = 0.85
  config.auto_merge_threshold = 0.95
end

module FactDb
  module TestHelpers
    def setup
      super
      clean_database!
    end

    def teardown
      clean_database!
      super
    end

    def clean_database!
      # Clear all tables in reverse dependency order
      Models::FactSource.delete_all
      Models::EntityMention.delete_all
      Models::Fact.delete_all
      Models::EntityAlias.delete_all
      Models::Entity.delete_all
      Models::Content.delete_all
    rescue ActiveRecord::StatementInvalid
      # Tables may not exist yet
    end

    def create_content(raw_text: "Test content", type: "document", captured_at: Time.current, **attrs)
      Models::Content.create!(
        raw_text: raw_text,
        content_hash: Digest::SHA256.hexdigest(raw_text + rand.to_s),
        content_type: type,
        captured_at: captured_at,
        source_metadata: {},
        **attrs
      )
    end

    def create_entity(name: "Test Entity", type: "person", **attrs)
      Models::Entity.create!(
        canonical_name: name,
        entity_type: type,
        resolution_status: attrs.delete(:resolution_status) || "resolved",
        metadata: attrs.delete(:metadata) || {},
        **attrs
      )
    end

    def create_fact(text: "Test fact", valid_at: Time.current, **attrs)
      Models::Fact.create!(
        fact_text: text,
        fact_hash: Digest::SHA256.hexdigest(text + rand.to_s),
        valid_at: valid_at,
        status: attrs.delete(:status) || "canonical",
        **attrs
      )
    end

    def create_clock
      FactDb.new
    end
  end
end

# Establish database connection for tests
begin
  FactDb::Database.establish_connection!
rescue StandardError => e
  puts "Warning: Could not connect to test database: #{e.message}"
  puts "Some tests may be skipped."
end
