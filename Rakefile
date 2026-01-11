# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task test: "db:reset:test"

namespace :db do
  desc "Drop the database"
  task :drop do
    require_relative "lib/fact_db"
    puts "Environment: #{FactDb.config.environment}"
    puts "Database: #{FactDb.config.database.name}"
    FactDb::Database.drop!
  end

  desc "Create the database"
  task :create do
    require_relative "lib/fact_db"
    puts "Environment: #{FactDb.config.environment}"
    puts "Database: #{FactDb.config.database.name}"
    FactDb::Database.create!
  end

  desc "Run database migrations"
  task :migrate do
    require_relative "lib/fact_db"
    puts "Environment: #{FactDb.config.environment}"
    puts "Database: #{FactDb.config.database.name}"
    FactDb::Database.migrate!
  end

  desc "Rollback the last migration"
  task :rollback do
    require_relative "lib/fact_db"
    puts "Environment: #{FactDb.config.environment}"
    puts "Database: #{FactDb.config.database.name}"
    FactDb::Database.rollback!
  end

  desc "Reset the database (drop, create, migrate) - honors FDB_ENV"
  task :reset do
    require_relative "lib/fact_db"
    puts "Environment: #{FactDb.config.environment}"
    puts "Database: #{FactDb.config.database.name}"
    FactDb::Database.reset!
  end

  namespace :reset do
    def reset_for_environment(env_name)
      original_env = ENV["FDB_ENV"]
      ENV["FDB_ENV"] = env_name

      require_relative "lib/fact_db"
      Anyway::Settings.current_environment = env_name
      FactDb.reset_configuration!

      puts "Environment: #{FactDb.config.environment}"
      puts "Database: #{FactDb.config.database.name}"
      FactDb::Database.reset!
    ensure
      ENV["FDB_ENV"] = original_env
      Anyway::Settings.current_environment = original_env || "development"
      FactDb.reset_configuration!
    end

    desc "Reset development database"
    task :development do
      reset_for_environment("development")
    end

    desc "Reset test database"
    task :test do
      reset_for_environment("test")
    end

    desc "Reset demo database"
    task :demo do
      reset_for_environment("demo")
    end

    desc "Reset all databases (development, test, demo)"
    task :all do
      %w[development test demo].each do |env_name|
        puts "\n#{"=" * 50}"
        reset_for_environment(env_name)
      end
      puts "\n#{"=" * 50}"
      puts "All databases reset."
    end
  end

  desc "Clean up invalid aliases (pronouns, generic terms). Use EXECUTE=1 to apply changes."
  task :cleanup_aliases do
    require_relative "lib/fact_db"
    puts "Environment: #{FactDb.config.environment}"
    puts "Database: #{FactDb.config.database.name}"
    FactDb::Database.establish_connection!

    dry_run = ENV["EXECUTE"] != "1"
    stats = { checked: 0, removed: 0 }

    puts dry_run ? "\n=== DRY RUN ===" : "\n=== EXECUTING ==="
    puts

    FactDb::Models::Entity.not_merged.find_each do |entity|
      entity.aliases.each do |alias_record|
        stats[:checked] += 1
        next if FactDb::Validation::AliasFilter.valid?(alias_record.alias_text, canonical_name: entity.canonical_name)

        reason = FactDb::Validation::AliasFilter.rejection_reason(alias_record.alias_text, canonical_name: entity.canonical_name)
        puts "#{entity.canonical_name}: removing \"#{alias_record.alias_text}\" (#{reason})"
        alias_record.destroy unless dry_run
        stats[:removed] += 1
      end
    end

    puts "\nChecked: #{stats[:checked]}, Removed: #{stats[:removed]}"
    puts "\nRun with EXECUTE=1 to apply changes." if dry_run && stats[:removed] > 0
  end
end

task default: :test
