# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Set test environment BEFORE loading fact_db
ENV["FDB_ENV"] = "test"

require "minitest/autorun"
require "timecop"
require "fact_db"

# Configure for testing
FactDb.configure do |config|
  config.logger = Logger.new(File::NULL) # Silence logs in tests
end

module FactDb
  module TestHelpers
    def setup
      super
      clean_database!
    end

    def teardown
      Timecop.return
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
      Models::Source.delete_all
    rescue ActiveRecord::StatementInvalid
      # Tables may not exist yet
    end

    def create_source(content: "Test content", kind: "document", captured_at: Time.current, **attrs)
      Models::Source.create!(
        content: content,
        content_hash: Digest::SHA256.hexdigest(content + rand.to_s),
        kind: kind,
        captured_at: captured_at,
        metadata: {},
        **attrs
      )
    end

    def create_entity(name: "Test Entity", kind: "person", **attrs)
      Models::Entity.create!(
        name: name,
        kind: kind,
        resolution_status: attrs.delete(:resolution_status) || "resolved",
        metadata: attrs.delete(:metadata) || {},
        **attrs
      )
    end

    def create_fact(text: "Test fact", valid_at: Time.current, **attrs)
      Models::Fact.create!(
        text: text,
        digest: Digest::SHA256.hexdigest(text + rand.to_s),
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
  # Reset schema cache to pick up current schema
  ActiveRecord::Base.connection.schema_cache.clear!
  FactDb::Models::Entity.reset_column_information
  FactDb::Models::Source.reset_column_information
  FactDb::Models::Fact.reset_column_information
  FactDb::Models::EntityAlias.reset_column_information
  FactDb::Models::EntityMention.reset_column_information
  FactDb::Models::FactSource.reset_column_information
rescue StandardError => e
  puts "Warning: Could not connect to test database: #{e.message}"
  puts "Some tests may be skipped."
end
