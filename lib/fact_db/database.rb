# frozen_string_literal: true

require "active_record"
require "neighbor"

module FactDb
  module Database
    class << self
      def establish_connection!(config = FactDb.config)
        config.validate!
        # config.database is a ConfigSection (Hash subclass) - pass directly to AR
        ActiveRecord::Base.establish_connection(config.database)
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
        url = FactDb.config.database.url
        uri = URI.parse(url)
        uri.path = "/postgres"
        uri.to_s
      end
    end
  end
end
