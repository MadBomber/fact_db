#!/usr/bin/env ruby
# frozen_string_literal: true

# Conventions? bah-humbug;  Configure everything!!
#
# Configuration Example for FactDb
#
# This example demonstrates all the ways to configure FactDb:
# - Bundled defaults (shipped with the gem)
# - Environment variables (FDB_*)
# - XDG user config files (~/.config/fact_db/fact_db.yml)
# - Project config files (./config/fact_db.yml)
# - Local overrides (./config/fact_db.local.yml)
# - Programmatic configuration blocks
#
# Configuration priority (lowest to highest):
# 1. Bundled defaults
# 2. XDG user config
# 3. Project config
# 4. Local overrides
# 5. Environment variables
# 6. Programmatic (FactDb.configure block)

require "bundler/setup"
require "fact_db"

puts <<~HEADER
  ======================================================================
  FactDb Configuration Demo
  ======================================================================
HEADER

# =============================================================================
# Section 1: Understanding the Current Environment
# =============================================================================
puts "\n--- Section 1: Current Environment ---\n"

puts <<~ENV_DETECTION
  Environment detection priority: FDB_ENV > RAILS_ENV > RACK_ENV > 'development'
    FDB_ENV:   #{ENV['FDB_ENV'].inspect}
    RAILS_ENV: #{ENV['RAILS_ENV'].inspect}
    RACK_ENV:  #{ENV['RACK_ENV'].inspect}
    Detected:  #{FactDb.env}
ENV_DETECTION

# Environment helper methods
config = FactDb.config

puts <<~ENV_HELPERS

  Environment helpers (dynamically generated from defaults.yml):
    config.environment:  #{config.environment}
    config.production?:  #{config.production?}
    config.development?: #{config.development?}
    config.test?:        #{config.test?}
    config.demo?:        #{config.demo?}

  Valid environments defined in defaults.yml:
    #{FactDb::Config.valid_environments.join(', ')}
    Current environment valid?: #{config.valid_environment?}
ENV_HELPERS

# =============================================================================
# Section 2: Configuration File Locations
# =============================================================================
puts "\n--- Section 2: Configuration File Locations ---\n"

puts <<~CONFIG_SOURCES
  Configuration sources (lowest to highest priority):

  1. Bundled defaults (ships with gem):
     #{FactDb::Config::DEFAULTS_PATH}

  2. XDG user config paths (checked in order):
CONFIG_SOURCES

FactDb::Config.xdg_config_paths.each_with_index do |path, i|
  exists = File.exist?(File.join(path, "fact_db.yml"))
  status = exists ? "(exists)" : "(not found)"
  puts "     #{i + 1}. #{path}/fact_db.yml #{status}"
end

active_xdg = FactDb::Config.active_xdg_config_file

puts <<~MORE_SOURCES

     Active XDG config: #{active_xdg || '(none)'}

  3. Project config:  ./config/fact_db.yml
     Exists: #{File.exist?('./config/fact_db.yml')}

  4. Local overrides: ./config/fact_db.local.yml (typically gitignored)
     Exists: #{File.exist?('./config/fact_db.local.yml')}

  5. Environment variables: FDB_* (see Section 4)

  6. Programmatic: FactDb.configure { |c| ... } (see Section 5)
MORE_SOURCES

# =============================================================================
# Section 3: Accessing Configuration Values
# =============================================================================
puts "\n--- Section 3: Accessing Configuration Values ---\n"

puts <<~DATABASE_CONFIG
  Database configuration (AR-compatible Hash with dot notation):
    config.database.adapter:  #{config.database.adapter.inspect}
    config.database.url:      #{config.database.url.inspect}
    config.database.host:     #{config.database.host.inspect}
    config.database.port:     #{config.database.port.inspect}
    config.database.database: #{config.database.database.inspect}
    config.database.username: #{config.database.username.inspect}
    config.database.pool:     #{config.database.pool.inspect}
    config.database.timeout:  #{config.database.timeout.inspect}

  Database helper method:
    config.database_configured?: #{config.database_configured?}

  LLM configuration:
    config.llm.provider: #{config.llm.provider.inspect}
    config.llm.model:    #{config.llm.model.inspect}
    config.llm.api_key:  #{config.llm.api_key ? '[REDACTED]' : 'nil'}

  Embedding configuration:
    config.embedding.generator:  #{config.embedding.generator.inspect}
    config.embedding.dimensions: #{config.embedding.dimensions.inspect}

  Ranking weights (for relevance scoring):
    config.ranking.ts_rank_weight:            #{config.ranking.ts_rank_weight}
    config.ranking.vector_similarity_weight:  #{config.ranking.vector_similarity_weight}
    config.ranking.entity_mention_weight:     #{config.ranking.entity_mention_weight}
    config.ranking.direct_answer_weight:      #{config.ranking.direct_answer_weight}
    config.ranking.term_overlap_weight:       #{config.ranking.term_overlap_weight}
    config.ranking.relationship_match_weight: #{config.ranking.relationship_match_weight}
    config.ranking.confidence_weight:         #{config.ranking.confidence_weight}

  General settings:
    config.default_extractor:     #{config.default_extractor.inspect}
    config.fuzzy_match_threshold: #{config.fuzzy_match_threshold}
    config.auto_merge_threshold:  #{config.auto_merge_threshold}
    config.log_level:             #{config.log_level.inspect}
DATABASE_CONFIG

# =============================================================================
# Section 4: Environment Variables
# =============================================================================
puts "\n--- Section 4: Environment Variables ---\n"

puts <<~ENV_VARS
  Environment variables use the FDB_ prefix with double underscores for nesting.
  They have the HIGHEST priority (except for programmatic config).

  Examples:
    # Environment selection
    export FDB_ENV=production

    # Database configuration
    export FDB_DATABASE__URL=postgresql://user:pass@localhost:5432/fact_db
    export FDB_DATABASE__NAME=my_fact_db
    export FDB_DATABASE__HOST=db.example.com
    export FDB_DATABASE__PORT=5432
    export FDB_DATABASE__USER=dbuser
    export FDB_DATABASE__PASSWORD=secret
    export FDB_DATABASE__POOL_SIZE=10

    # LLM configuration
    export FDB_LLM__PROVIDER=anthropic
    export FDB_LLM__MODEL=claude-sonnet-4-20250514
    export FDB_LLM__API_KEY=sk-xxx

    # Embedding configuration
    export FDB_EMBEDDING__DIMENSIONS=1536

    # Ranking weights
    export FDB_RANKING__TS_RANK_WEIGHT=0.30
    export FDB_RANKING__VECTOR_SIMILARITY_WEIGHT=0.25

    # General settings
    export FDB_DEFAULT_EXTRACTOR=llm
    export FDB_FUZZY_MATCH_THRESHOLD=0.80
    export FDB_LOG_LEVEL=debug

  Currently set FDB_* environment variables:
ENV_VARS

fdb_vars = ENV.select { |k, _| k.start_with?("FDB_") }
if fdb_vars.empty?
  puts "    (none)"
else
  fdb_vars.each do |key, value|
    display_value = key.include?("KEY") || key.include?("PASSWORD") ? "[REDACTED]" : value
    puts "    #{key}=#{display_value}"
  end
end

# =============================================================================
# Section 5: Programmatic Configuration
# =============================================================================
puts "\n--- Section 5: Programmatic Configuration ---\n"

# Reset configuration to show before/after
FactDb.reset_configuration!

puts <<~PROGRAMMATIC_INTRO
  Use FactDb.configure to set values programmatically.
  This has the HIGHEST priority and overrides all other sources.

  Before programmatic configuration:
    log_level: #{FactDb.config.log_level.inspect}
    fuzzy_match_threshold: #{FactDb.config.fuzzy_match_threshold}
PROGRAMMATIC_INTRO

# Apply programmatic configuration
FactDb.configure do |c|
  # Scalar values
  c.log_level = :debug
  c.fuzzy_match_threshold = 0.75
  c.default_extractor = :llm

  # Nested values using dot notation
  c.ranking.ts_rank_weight = 0.30
  c.ranking.vector_similarity_weight = 0.35

  # Callable objects (not loaded from config files)
  c.logger = Logger.new($stdout, level: Logger::WARN)

  # Custom embedding generator (lambda or object responding to #call)
  # c.embedding_generator = ->(text) { OpenAI.embed(text) }

  # Custom LLM client
  # c.llm_client = MyCustomLLMClient.new
end

puts <<~AFTER_PROGRAMMATIC

  After programmatic configuration:
    log_level: #{FactDb.config.log_level.inspect}
    fuzzy_match_threshold: #{FactDb.config.fuzzy_match_threshold}
    default_extractor: #{FactDb.config.default_extractor.inspect}
    ranking.ts_rank_weight: #{FactDb.config.ranking.ts_rank_weight}
    ranking.vector_similarity_weight: #{FactDb.config.ranking.vector_similarity_weight}
    logger: #{FactDb.config.logger.class}
AFTER_PROGRAMMATIC

# =============================================================================
# Section 6: Config File Examples
# =============================================================================
puts "\n--- Section 6: Config File Examples ---\n"

puts <<~CONFIG_FILES
  XDG User Config (~/.config/fact_db/fact_db.yml):
    ---
    # User-wide defaults (applies to all projects)
    database:
      host: localhost
      user: myuser

    llm:
      provider: anthropic
      api_key: sk-my-api-key  # Or use FDB_LLM__API_KEY env var

    embedding:
      dimensions: 1536

  Project Config (./config/fact_db.yml):
    ---
    # Environment-specific configuration
    development:
      database:
        name: myapp_development
      log_level: debug

    test:
      database:
        name: myapp_test
        pool_size: 2
      log_level: warn

    production:
      database:
        name: myapp_production
        pool_size: 25
      log_level: info
      fuzzy_match_threshold: 0.90

  Local Overrides (./config/fact_db.local.yml):
    ---
    # Personal overrides (gitignored)
    # Great for API keys and local database credentials
    llm:
      api_key: sk-my-personal-key

    database:
      password: my_local_password
CONFIG_FILES

# =============================================================================
# Section 7: Database URL Reconciliation
# =============================================================================
puts "\n--- Section 7: Database URL Reconciliation ---\n"

puts <<~URL_RECONCILIATION
  FactDb automatically reconciles database.url with individual components.

  If you set database.url, components are extracted:
    FDB_DATABASE__URL=postgresql://user:pass@db.example.com:5432/mydb
    => database.host = 'db.example.com'
    => database.port = 5432
    => database.database = 'mydb'
    => database.username = 'user'

  If you set components, URL is built automatically:
    FDB_DATABASE__NAME=mydb
    FDB_DATABASE__HOST=db.example.com
    => database.url = 'postgresql://user@db.example.com:5432/mydb'

  Current reconciled database config:
    URL:  #{FactDb.config.database.url}
    Hash: #{FactDb.config.database.to_h.inspect}
URL_RECONCILIATION

# =============================================================================
# Section 8: Validation
# =============================================================================
puts "\n--- Section 8: Configuration Validation ---\n"

puts <<~VALIDATION
  Call config.validate! to ensure configuration is complete.
  This checks:
    - Database is configured (URL or name)
    - Callable objects are valid (logger, embedding_generator, llm_client)

VALIDATION

begin
  FactDb.config.validate!
  puts "  Configuration is valid!"
rescue FactDb::ConfigurationError => e
  puts "  Configuration error: #{e.message}"
end

# =============================================================================
# Section 9: Resetting Configuration
# =============================================================================
puts "\n--- Section 9: Resetting Configuration ---\n"

current_log_level = FactDb.config.log_level.inspect

puts <<~RESET_INTRO
  Use FactDb.reset_configuration! to reload from all sources.
  This is useful after changing environment variables or config files.

  Before reset - log_level: #{current_log_level}
RESET_INTRO

FactDb.reset_configuration!
puts "  After reset - log_level:  #{FactDb.config.log_level.inspect}"

# =============================================================================
# Section 10: Quick Reference
# =============================================================================
puts "\n--- Section 10: Quick Reference ---\n"

puts <<~REFERENCE
  Environment Variables:
    FDB_ENV                         - Set environment (development/test/production)
    FDB_DATABASE__URL               - Full database connection URL
    FDB_DATABASE__NAME              - Database name
    FDB_LLM__PROVIDER               - LLM provider (anthropic/openai)
    FDB_LLM__API_KEY                - API key for LLM

  Config Files (in priority order):
    lib/fact_db/config/defaults.yml - Bundled defaults (lowest)
    ~/.config/fact_db/fact_db.yml   - XDG user config
    ./config/fact_db.yml            - Project config
    ./config/fact_db.local.yml      - Local overrides (gitignored)

  Ruby API:
    FactDb.env                      - Current environment name
    FactDb.config                   - Configuration object
    FactDb.configure { |c| ... }    - Programmatic configuration
    FactDb.reset_configuration!     - Reload from all sources

  Config Sections (Hash subclasses with dot notation):
    config.database                 - AR-compatible Hash
    config.database.host            - Dot notation access
    config.database[:host]          - Hash bracket access
    config.llm                      - LLM configuration Hash
    config.embedding                - Embedding configuration Hash
    config.ranking                  - Ranking weights Hash
    config.validate!                - Validate configuration

  ======================================================================
  Configuration Demo Complete!
  ======================================================================
REFERENCE
