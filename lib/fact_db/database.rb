# frozen_string_literal: true

require "active_record"
require "neighbor"

module FactDb
  module Database
    class << self
      def establish_connection!(config = FactDb.config)
        # config.database is a ConfigSection - convert to AR-compatible hash
        ActiveRecord::Base.establish_connection(ar_connection_hash(config.database))
        ActiveRecord::Base.logger = config.logger if config.logger
      end

      def connected?
        ActiveRecord::Base.connected?
      end

      def drop!
        db_name = FactDb.config.database.name
        ActiveRecord::Base.connection.disconnect! if connected?
        ActiveRecord::Base.establish_connection(maintenance_database_url)
        ActiveRecord::Base.connection.drop_database(db_name)
        puts "Dropped database '#{db_name}'"
      end

      def create!
        db_name = FactDb.config.database.name
        ActiveRecord::Base.establish_connection(maintenance_database_url)
        ActiveRecord::Base.connection.create_database(db_name)
        puts "Created database '#{db_name}'"
      end

      def migrate!
        establish_connection! unless connected?
        migrations_path = File.expand_path("../../db/migrate", __dir__)
        ActiveRecord::MigrationContext.new(migrations_path).migrate
      end

      def rollback!(steps = 1)
        establish_connection! unless connected?
        migrations_path = File.expand_path("../../db/migrate", __dir__)
        ActiveRecord::MigrationContext.new(migrations_path).rollback(steps)
      end

      def reset!
        drop! rescue nil
        create!
        migrate!
      end

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
