# frozen_string_literal: true

require "myway_config"
require "logger"

# Configure MywayConfig to use FDB_ENV for environment detection
Anyway::Settings.current_environment = ENV["FDB_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"

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
    config_name :fact_db
    env_prefix :fdb
    defaults_path File.expand_path("config/defaults.yml", __dir__)
    auto_configure!

    # ==========================================================================
    # Callable Accessors (not loaded from config sources)
    # ==========================================================================

    attr_accessor :embedding_generator, :llm_client, :logger

    # ==========================================================================
    # Callbacks
    # ==========================================================================

    on_load :setup_defaults

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

    private

    def setup_defaults
      @logger ||= build_default_logger
    end

    def build_default_logger
      logger = Logger.new($stdout)
      logger.level = log_level || :info
      logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} -- FactDb: #{msg}\n"
      end
      logger
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
