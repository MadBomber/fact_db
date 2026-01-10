# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

namespace :db do
  desc "Run database migrations"
  task :migrate do
    require_relative "lib/fact_db"
    FactDb.configure do |config|
      config.database.url = ENV.fetch("DATABASE_URL")
    end
    FactDb::Database.migrate!
  end

  desc "Rollback the last migration"
  task :rollback do
    require_relative "lib/fact_db"
    FactDb.configure do |config|
      config.database.url = ENV.fetch("DATABASE_URL")
    end
    FactDb::Database.rollback!
  end

  desc "Reset the database (drop, create, migrate)"
  task :reset do
    require_relative "lib/fact_db"
    FactDb.configure do |config|
      config.database.url = ENV.fetch("DATABASE_URL")
    end
    FactDb::Database.reset!
  end

  desc "Clean up invalid aliases (pronouns, generic terms). Use EXECUTE=1 to apply changes."
  task :cleanup_aliases do
    require_relative "lib/fact_db"
    FactDb.configure do |config|
      config.database.url = ENV.fetch("DATABASE_URL")
    end
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
