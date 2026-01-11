# frozen_string_literal: true

require "myway_config"
require "logger"

# Configure MywayConfig to use FDB_ENV for environment detection
Anyway::Settings.current_environment = ENV["FDB_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"

# Define Config class first to establish superclass before loading submodules
module FactDb
  class Config < MywayConfig::Base
  end
end

require_relative "config/section"
require_relative "config/validator"
require_relative "config/database"
require_relative "config/builder"

module FactDb
  # FactDb Configuration using MywayConfig
  #
  # Schema is defined in lib/fact_db/config/defaults.yml (single source of truth)
  #
  # All config sections return ConfigSections with symbol keys:
  #   FactDb.config.database  # => ConfigSection with {adapter: "postgresql", host: "localhost", ...}
  #   FactDb.config.llm       # => ConfigSection with {provider: :anthropic, model: "claude-...", ...}
  #   FactDb.config.embedding # => ConfigSection with {generator: nil, dimensions: 1536}
  #   FactDb.config.ranking   # => ConfigSection with {ts_rank_weight: 0.25, ...}
  #
  # Access values via hash keys or dot notation:
  #   FactDb.config.database[:host]
  #   FactDb.config.database.host
  #   FactDb.config.llm[:provider]
  #   FactDb.config.llm.provider
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
  # @example Configure with Ruby block
  #   FactDb.configure do |config|
  #     config.llm[:provider] = :openai
  #     config.llm[:model] = "gpt-4o-mini"
  #   end
  #
  class Config < MywayConfig::Base
    include Validator
    include Database
    include Builder

    config_name :fact_db
    env_prefix :fdb
    defaults_path File.expand_path("config/defaults.yml", __dir__)
    auto_configure!

    # ==========================================================================
    # Type Coercion (custom coercions beyond auto_configure!)
    # ==========================================================================

    coerce_types(
      # Sections -> ConfigSection objects (with schema defaults merged)
      database: config_section_coercion(:database),
      embedding: config_section_coercion(:embedding),
      llm: config_section_coercion(:llm),
      ranking: config_section_coercion(:ranking),

      # Top-level symbols
      default_extractor: to_symbol,
      log_level: to_symbol,

      # Top-level floats
      fuzzy_match_threshold: :float,
      auto_merge_threshold: :float
    )

    # ==========================================================================
    # Callbacks
    # ==========================================================================

    on_load :coerce_nested_types, :build_database_section, :validate_config, :setup_defaults

    # ==========================================================================
    # Section Accessors (return ConfigSection - Hash subclass with dot notation)
    # ==========================================================================
    #
    # These override the attr_config getters to return processed ConfigSection
    # objects. The raw data is stored in @values[:section_name] by MywayConfig.
    #

    # @return [ConfigSection] AR-compatible database configuration
    def database
      @_database_section
    end

    # @return [ConfigSection] embedding configuration
    def embedding
      @_embedding_section ||= build_embedding_section
    end

    # @return [ConfigSection] LLM configuration
    def llm
      @_llm_section ||= build_llm_section
    end

    # @return [ConfigSection] ranking weights configuration
    def ranking
      @_ranking_section ||= build_ranking_section
    end

    # Access raw config data (from MywayConfig's @values hash)
    def database_raw
      @values[:database]
    end

    def embedding_raw
      @values[:embedding]
    end

    def llm_raw
      @values[:llm]
    end

    def ranking_raw
      @values[:ranking]
    end

    # ==========================================================================
    # Callable Accessors (not loaded from config sources)
    # ==========================================================================

    attr_accessor :embedding_generator, :llm_client, :logger

    # ==========================================================================
    # XDG Config Path Helpers
    # ==========================================================================

    def self.xdg_config_paths
      MywayConfig::Loaders::XdgConfigLoader.config_paths(:fact_db)
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
      MywayConfig::Loaders::XdgConfigLoader.find_config_file(:fact_db)
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
      if database_raw&.port && !database_raw.port.is_a?(Integer)
        database_raw.port = database_raw.port.to_i
      end
      if database_raw&.pool_size && !database_raw.pool_size.is_a?(Integer)
        database_raw.pool_size = database_raw.pool_size.to_i
      end
      if database_raw&.timeout && !database_raw.timeout.is_a?(Integer)
        database_raw.timeout = database_raw.timeout.to_i
      end

      # Coerce embedding dimensions
      if embedding_raw&.dimensions && !embedding_raw.dimensions.is_a?(Integer)
        embedding_raw.dimensions = embedding_raw.dimensions.to_i
      end
    end

    # ==========================================================================
    # Build Section ConfigSections (lazy-loaded except database)
    # ==========================================================================

    def build_embedding_section
      raw = embedding_raw
      return ConfigSection.new unless raw

      ConfigSection.new(
        generator: raw.generator,
        dimensions: raw.dimensions&.to_i
      )
    end

    def build_llm_section
      raw = llm_raw
      return ConfigSection.new unless raw

      provider = raw.provider
      provider = provider.to_sym if provider && !provider.is_a?(Symbol)

      ConfigSection.new(
        client: raw.client,
        provider: provider,
        model: raw.model,
        api_key: raw.api_key
      )
    end

    def build_ranking_section
      raw = ranking_raw
      return ConfigSection.new unless raw

      ConfigSection.new(
        ts_rank_weight: raw.ts_rank_weight&.to_f,
        vector_similarity_weight: raw.vector_similarity_weight&.to_f,
        entity_mention_weight: raw.entity_mention_weight&.to_f,
        direct_answer_weight: raw.direct_answer_weight&.to_f,
        term_overlap_weight: raw.term_overlap_weight&.to_f,
        relationship_match_weight: raw.relationship_match_weight&.to_f,
        confidence_weight: raw.confidence_weight&.to_f
      )
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
