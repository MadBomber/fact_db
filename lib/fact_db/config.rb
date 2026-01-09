# frozen_string_literal: true

require "anyway_config"
require "logger"
require "yaml"

module FactDb
  ENVIRONMENTS = %w[development test production].freeze

  def self.env
    @env ||= ENV.fetch("FDB_ENV") { ENV.fetch("RAILS_ENV") { ENV.fetch("RACK_ENV", "development") } }
  end

  def self.env=(value)
    @env = value.to_s
  end

  class Config < Anyway::Config
    config_name :fact_db
    env_prefix :fdb

    DEFAULTS_PATH = File.expand_path("config/defaults.yml", __dir__).freeze

    class << self
      def load_defaults
        yaml = YAML.load_file(DEFAULTS_PATH) || {}
        common = yaml["common"] || {}
        env_config = yaml[FactDb.env] || {}
        deep_merge(common, env_config)
      end

      def deep_merge(base, override)
        base.merge(override) do |_key, base_val, override_val|
          if base_val.is_a?(Hash) && override_val.is_a?(Hash)
            deep_merge(base_val, override_val)
          else
            override_val.nil? ? base_val : override_val
          end
        end
      end

      def flatten_hash(hash, prefix = nil)
        hash.each_with_object({}) do |(key, value), result|
          attr_name = prefix ? "#{prefix}_#{key}" : key.to_s
          if value.is_a?(Hash)
            result.merge!(flatten_hash(value, attr_name))
          else
            result[attr_name.to_sym] = value
          end
        end
      end

      def define_attributes_from_defaults!
        defaults = flatten_hash(load_defaults)
        defaults.each do |attr_name, default_value|
          if default_value.nil?
            attr_config attr_name
          else
            attr_config attr_name => default_value
          end
        end
      end
    end

    define_attributes_from_defaults!

    def llm_client
      return super if super
      return nil unless llm_provider

      @llm_client ||= LLM::Adapter.new(
        provider: llm_provider.to_sym,
        model: llm_model,
        api_key: llm_api_key
      )
    end

    def logger
      super || Logger.new($stdout, level: log_level.to_sym)
    end

    def validate!
      raise ConfigurationError, "Database URL required" unless database_url

      self
    end
  end

  class << self
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
