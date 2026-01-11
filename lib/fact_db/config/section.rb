# frozen_string_literal: true

module FactDb
  # ConfigSection extends Hash to provide method access to configuration values.
  #
  # It's a real Hash (usable by ActiveRecord, etc.) but also supports dot notation:
  #
  # @example Hash-style access (for ActiveRecord compatibility)
  #   ActiveRecord::Base.establish_connection(FactDb.config.database)
  #   FactDb.config.database[:host]  # => 'localhost'
  #
  # @example Method-style access (for convenience)
  #   FactDb.config.database.host    # => 'localhost'
  #   FactDb.config.database.port    # => 5432
  #
  # @example Setting values
  #   FactDb.config.database.host = 'db.example.com'
  #   FactDb.config.database[:host] = 'db.example.com'
  #
  class ConfigSection < Hash
    def initialize(hash = {})
      super()
      (hash || {}).each do |key, value|
        self[key.to_sym] = value.is_a?(Hash) ? ConfigSection.new(value) : value
      end
    end

    def method_missing(method, *args, &block)
      key = method.to_s
      if key.end_with?("=")
        self[key.chomp("=").to_sym] = args.first
      elsif key?(method)
        self[method]
      else
        nil
      end
    end

    def respond_to_missing?(method, include_private = false)
      key = method.to_s.chomp("=").to_sym
      key?(key) || super
    end

    # Override to_h to recursively convert nested ConfigSections
    def to_h
      transform_values do |v|
        v.is_a?(ConfigSection) ? v.to_h : v
      end
    end

    # Deep merge with another hash
    def deep_merge(other)
      other_hash = other.is_a?(ConfigSection) ? other.to_h : (other || {})
      ConfigSection.new(recursive_merge(to_h, other_hash))
    end

    private

    def recursive_merge(base, overlay)
      base.merge(overlay) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          recursive_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
  end
end
