# frozen_string_literal: true

require "active_record"
require "neighbor"

module FactDb
  # Database management module for FactDb
  #
  # Provides class methods for establishing database connections, running
  # migrations, and managing database lifecycle (create, drop, reset).
  #
  # @example Establish connection and run migrations
  #   FactDb::Database.establish_connection!
  #   FactDb::Database.migrate!
  #
  # @example Reset database for testing
  #   FactDb::Database.reset!
  #
  module Database
    class << self
      # Establishes an ActiveRecord database connection
      #
      # Uses configuration from FactDb.config by default. Sets up the logger
      # if configured.
      #
      # @param config [FactDb::Config] configuration object (defaults to FactDb.config)
      # @return [void]
      def establish_connection!(config = FactDb.config)
        # config.database is a ConfigSection - convert to AR-compatible hash
        ActiveRecord::Base.establish_connection(ar_connection_hash(config.database))
        ActiveRecord::Base.logger = config.logger if config.logger
      end

      # Checks if a database connection is established
      #
      # @return [Boolean] true if connected to database
      def connected?
        ActiveRecord::Base.connected?
      end

      # Drops the database
      #
      # Disconnects from the current database, connects to postgres maintenance
      # database, and drops the configured database.
      #
      # @return [void]
      def drop!
        db_name = FactDb.config.database.name
        ActiveRecord::Base.connection.disconnect! if connected?
        ActiveRecord::Base.establish_connection(maintenance_database_url)
        ActiveRecord::Base.connection.drop_database(db_name)
        puts "Dropped database '#{db_name}'"
      end

      # Creates the database
      #
      # Connects to postgres maintenance database and creates the configured database.
      #
      # @return [void]
      def create!
        db_name = FactDb.config.database.name
        ActiveRecord::Base.establish_connection(maintenance_database_url)
        ActiveRecord::Base.connection.create_database(db_name)
        puts "Created database '#{db_name}'"
      end

      # Runs all pending migrations
      #
      # Establishes connection if needed and runs migrations from db/migrate.
      #
      # @return [void]
      def migrate!
        establish_connection!
        migrations_path = File.expand_path("../../db/migrate", __dir__)
        ActiveRecord::MigrationContext.new(migrations_path).migrate
      end

      # Rolls back migrations
      #
      # @param steps [Integer] number of migrations to rollback (default: 1)
      # @return [void]
      def rollback!(steps = 1)
        establish_connection! unless connected?
        migrations_path = File.expand_path("../../db/migrate", __dir__)
        ActiveRecord::MigrationContext.new(migrations_path).rollback(steps)
      end

      # Drops, creates, and migrates the database
      #
      # Convenience method to completely reset the database to a clean state.
      # Ignores errors when dropping (database may not exist).
      #
      # @return [void]
      def reset!
        drop! rescue nil
        create!
        migrate!
      end

      # Returns the current schema version
      #
      # @return [Integer] the latest migration version number, or 0 if no migrations
      def schema_version
        establish_connection! unless connected?
        ActiveRecord::SchemaMigration.all.map(&:version).max || 0
      end

      private

      def maintenance_database_url
        db = FactDb.config.database
        url = db.url || build_database_url(db, "postgres")
        uri = URI.parse(url)
        uri.path = "/postgres"
        uri.to_s
      end

      def build_database_url(db, database_name = nil)
        host = db.host || "localhost"
        port = db.port || 5432
        name = database_name || db.name
        user = db.username || ENV["USER"]

        auth = user ? "#{user}@" : ""
        "postgresql://#{auth}#{host}:#{port}/#{name}"
      end

      # Convert config to AR-compatible hash (name -> database)
      def ar_connection_hash(db)
        h = db.to_h
        h[:database] = h.delete(:name) if h[:name] && !h[:database]
        h
      end
    end
  end
end
