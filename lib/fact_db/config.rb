# frozen_string_literal: true

require "anyway_config"
require "logger"
require "yaml"

# Configure Anyway Config to use FDB_ENV for environment detection
Anyway::Settings.current_environment = ENV["FDB_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"

# Define Config class first to establish superclass
module FactDb
  class Config < Anyway::Config
  end
end

require_relative "config/section"
require_relative "config/validator"
require_relative "config/database"
require_relative "config/builder"

module FactDb
  # FactDb Configuration using Anyway Config
  #
  # Schema is defined in lib/fact_db/config/defaults.yml (single source of truth)
  # Configuration uses nested sections for better organization:
  #   - FactDb.config.database.url
  #   - FactDb.config.database.pool_size
  #   - FactDb.config.llm.provider
  #   - FactDb.config.ranking.ts_rank_weight
  #
  # Configuration sources (lowest to highest priority):
  # 1. Bundled defaults: lib/fact_db/config/defaults.yml (ships with gem)
  # 2. XDG user config:
  #    - ~/Library/Application Support/fact_db/fact_db.yml (macOS only)
  #    - ~/.config/fact_db/fact_db.yml (XDG default)
  #    - $XDG_CONFIG_HOME/fact_db/fact_db.yml (if XDG_CONFIG_HOME is set)
  # 3. Project config: ./config/fact_db.yml (environment-specific)
  # 4. Local overrides: ./config/fact_db.local.yml (gitignored)
  # 5. Environment variables (FDB_*)
  # 6. Explicit values passed to configure block
  #
  # @example Configure with environment variables
  #   export FDB_DATABASE__URL=postgresql://localhost/fact_db_development
  #   export FDB_LLM__PROVIDER=openai
  #   export FDB_LLM__API_KEY=sk-xxx
  #
  # @example Configure with XDG user config (~/.config/fact_db/fact_db.yml)
  #   database:
  #     url: postgresql://localhost/fact_db_development
  #   llm:
  #     provider: anthropic
  #     model: claude-sonnet-4-20250514
  #
  # @example Configure with Ruby block
  #   FactDb.configure do |config|
  #     config.llm.provider = :openai
  #     config.llm.model = "gpt-4o-mini"
  #   end
  #
  class Config
    include Validator
    include Database
    include Builder

    config_name :fact_db
    env_prefix :fdb

    # ==========================================================================
    # Schema Definition (loaded from defaults.yml - single source of truth)
    # ==========================================================================

    # Path to bundled defaults file (defines both schema and default values)
    DEFAULTS_PATH = File.expand_path("config/defaults.yml", __dir__).freeze

    # Load schema from defaults.yml at class definition time
    begin
      defaults_content = File.read(DEFAULTS_PATH)
      raw_yaml = YAML.safe_load(
        defaults_content,
        permitted_classes: [Symbol],
        symbolize_names: true,
        aliases: true
      ) || {}
      SCHEMA = raw_yaml[:defaults] || {}
    rescue StandardError => e
      warn "FactDb: Could not load schema from #{DEFAULTS_PATH}: #{e.message}"
      SCHEMA = {}
    end

    # Nested section attributes (defined as hashes, converted to ConfigSection)
    attr_config :database, :embedding, :llm, :ranking

    # Top-level scalar attributes
    attr_config :default_extractor, :fuzzy_match_threshold, :auto_merge_threshold, :log_level

    # Custom environment detection: FDB_ENV > RAILS_ENV > RACK_ENV > 'development'
    class << self
      def env
        Anyway::Settings.current_environment ||
          ENV["FDB_ENV"] ||
          ENV["RAILS_ENV"] ||
          ENV["RACK_ENV"] ||
          "development"
      end
    end

    # ==========================================================================
    # Type Coercion
    # ==========================================================================

    TO_SYMBOL = ->(v) { v.nil? ? nil : v.to_s.to_sym }

    # Create a coercion that merges incoming value with SCHEMA defaults for a section.
    # This ensures env vars like FDB_DATABASE__URL don't lose other defaults.
    def self.config_section_with_defaults(section_key)
      defaults = SCHEMA[section_key] || {}
      ->(v) {
        return v if v.is_a?(ConfigSection)
        incoming = v || {}
        # Deep merge: defaults first, then overlay incoming values
        merged = deep_merge_hashes(defaults.dup, incoming)
        ConfigSection.new(merged)
      }
    end

    # Deep merge helper for coercion
    def self.deep_merge_hashes(base, overlay)
      base.merge(overlay) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge_hashes(old_val, new_val)
        else
          new_val.nil? ? old_val : new_val
        end
      end
    end

    coerce_types(
      # Nested sections -> ConfigSection objects (with SCHEMA defaults merged)
      database: config_section_with_defaults(:database),
      embedding: config_section_with_defaults(:embedding),
      llm: config_section_with_defaults(:llm),
      ranking: config_section_with_defaults(:ranking),

      # Top-level symbols
      default_extractor: TO_SYMBOL,
      log_level: TO_SYMBOL,

      # Top-level floats
      fuzzy_match_threshold: :float,
      auto_merge_threshold: :float
    )

    # ==========================================================================
    # Callbacks
    # ==========================================================================

    on_load :coerce_nested_types, :reconcile_database_config, :validate_config, :setup_defaults

    # ==========================================================================
    # Callable Accessors (not loaded from config sources)
    # ==========================================================================

    attr_accessor :embedding_generator, :llm_client, :logger

    # ==========================================================================
    # Convenience Accessors (for common nested values)
    # ==========================================================================

    # LLM convenience accessors
    def llm_provider
      provider = llm&.provider
      provider.is_a?(Symbol) ? provider : provider&.to_sym
    end

    def llm_model
      llm&.model
    end

    def llm_api_key
      llm&.api_key
    end

    # Embedding convenience accessors
    def embedding_dimensions
      embedding&.dimensions.to_i
    end

    # Ranking convenience accessors
    def ranking_ts_rank_weight
      ranking&.ts_rank_weight.to_f
    end

    def ranking_vector_similarity_weight
      ranking&.vector_similarity_weight.to_f
    end

    def ranking_entity_mention_weight
      ranking&.entity_mention_weight.to_f
    end

    def ranking_direct_answer_weight
      ranking&.direct_answer_weight.to_f
    end

    def ranking_term_overlap_weight
      ranking&.term_overlap_weight.to_f
    end

    def ranking_relationship_match_weight
      ranking&.relationship_match_weight.to_f
    end

    def ranking_confidence_weight
      ranking&.confidence_weight.to_f
    end

    # ==========================================================================
    # Environment Helpers
    # ==========================================================================

    def test?
      self.class.env == "test"
    end

    def development?
      self.class.env == "development"
    end

    def production?
      self.class.env == "production"
    end

    def environment
      self.class.env
    end

    # ==========================================================================
    # Environment Validation
    # ==========================================================================

    # Returns list of valid environment names from bundled defaults
    #
    # @return [Array<Symbol>] valid environment names (e.g., [:development, :production, :test])
    def self.valid_environments
      FactDb::Loaders::DefaultsLoader.valid_environments
    end

    # Check if current environment is valid (defined in config)
    #
    # @return [Boolean] true if environment has a config section
    def self.valid_environment?
      FactDb::Loaders::DefaultsLoader.valid_environment?(env)
    end

    # Instance method delegates
    def valid_environment?
      self.class.valid_environment?
    end

    # ==========================================================================
    # XDG Config Path Helpers
    # ==========================================================================

    def self.xdg_config_paths
      FactDb::Loaders::XdgConfigLoader.config_paths
    end

    def self.xdg_config_file
      xdg_home = ENV["XDG_CONFIG_HOME"]
      base = if xdg_home && !xdg_home.empty?
        xdg_home
      else
        File.expand_path("~/.config")
      end
      File.join(base, "fact_db", "fact_db.yml")
    end

    def self.active_xdg_config_file
      FactDb::Loaders::XdgConfigLoader.find_config_file("fact_db")
    end

    # ==========================================================================
    # Validation
    # ==========================================================================

    def validate!
      validate_database!
      validate_callables
      validate_logger
      self
    end

    private

    # ==========================================================================
    # Type Coercion Callback
    # ==========================================================================

    def coerce_nested_types
      # Coerce database numeric fields to integers (env vars are always strings)
      if database&.port && !database.port.is_a?(Integer)
        database.port = database.port.to_i
      end
      if database&.pool_size && !database.pool_size.is_a?(Integer)
        database.pool_size = database.pool_size.to_i
      end
      if database&.timeout && !database.timeout.is_a?(Integer)
        database.timeout = database.timeout.to_i
      end

      # Coerce embedding dimensions
      if embedding&.dimensions && !embedding.dimensions.is_a?(Integer)
        embedding.dimensions = embedding.dimensions.to_i
      end
    end
  end

  # ==========================================================================
  # Module-level Configuration API
  # ==========================================================================

  class << self
    def env
      @env ||= ENV.fetch("FDB_ENV") { ENV.fetch("RAILS_ENV") { ENV.fetch("RACK_ENV", "development") } }
    end

    def env=(value)
      @env = value.to_s
    end

    def config
      @config ||= Config.new
    end

    def configure
      yield(config) if block_given?
      config
    end

    def reset_configuration!
      @config = nil
    end
  end
end

# Register custom loaders after Config class is defined
# Order matters: defaults (lowest priority) -> XDG -> project config -> ENV (highest)
require_relative "loaders/defaults_loader"
require_relative "loaders/xdg_config_loader"
