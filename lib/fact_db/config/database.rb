# frozen_string_literal: true

require "uri"

module FactDb
  class Config
    module Database
      # ==========================================================================
      # Database Configuration
      # ==========================================================================
      #
      # FactDb.config.database returns a ConfigSection (Hash subclass) suitable
      # for ActiveRecord, with both hash and dot notation access:
      #
      # @example Hash-style (for ActiveRecord)
      #   ActiveRecord::Base.establish_connection(FactDb.config.database)
      #
      # @example Dot notation
      #   FactDb.config.database.host     # => "localhost"
      #   FactDb.config.database.database # => "fact_db_development"
      #
      # @example Hash bracket notation
      #   FactDb.config.database[:host]   # => "localhost"
      #
      # Configuration is loaded from YAML/env vars with these keys:
      #   - url, host, port, name, user, password, pool_size, timeout, adapter
      #
      # These are mapped to ActiveRecord-compatible keys:
      #   - name      -> database
      #   - user      -> username
      #   - pool_size -> pool
      #   - adapter   -> adapter (pg -> postgresql)
      #
      # ==========================================================================

      # Check if database is configured
      #
      # @return [Boolean] true if database URL or name is configured
      def database_configured?
        db = database
        return false unless db

        url = db[:url]
        name = db[:database]
        (url && !url.empty?) || (name && !name.empty?)
      end

      # Validate that database is configured for the current environment
      #
      # @raise [FactDb::ConfigurationError] if database is not configured
      # @return [true] if database is configured
      def validate_database!
        return true if database_configured?

        raise ConfigurationError,
          "No database configured for environment '#{environment}'. " \
          "Set FDB_DATABASE__URL or FDB_DATABASE__NAME, " \
          "or add database.name to the '#{environment}:' section in your config."
      end

      private

      # ==========================================================================
      # Database Configuration Building
      # ==========================================================================

      # Called from on_load callback to build the AR-compatible ConfigSection
      def build_database_section
        raw = database_raw
        return @_database_section = ConfigSection.new unless raw

        # First reconcile URL and components
        reconcile_database_config(raw)

        # Build AR-compatible ConfigSection
        # Include both :database (AR) and :name (FactDb internal use) for compatibility
        @_database_section = ConfigSection.new(
          adapter: normalize_adapter(raw.adapter),
          url: raw.url,
          host: raw.host,
          port: raw.port&.to_i,
          database: raw.name,
          name: raw.name,
          username: raw.user,
          password: raw.password,
          pool: raw.pool_size&.to_i,
          timeout: raw.timeout&.to_i,
          encoding: "unicode",
          prepared_statements: false,
          advisory_locks: false
        )
      end

      def normalize_adapter(adapter)
        case adapter&.to_s
        when "pg", "postgres", "postgresql"
          "postgresql"
        when nil, ""
          "postgresql"
        else
          adapter.to_s
        end
      end

      # ==========================================================================
      # Database Configuration Reconciliation
      # ==========================================================================
      #
      # Ensures url and components are synchronized:
      #
      # 1. If url exists:
      #    - Extract all components from the URL
      #    - Populate missing component fields from URL
      #
      # 2. If url is missing but components exist:
      #    - Verify minimum required components (at least name)
      #    - Build and set url from components
      #
      # ==========================================================================

      def reconcile_database_config(raw)
        url = raw.url
        has_url = url && !url.empty?

        if has_url
          reconcile_from_url(raw)
        else
          reconcile_from_components(raw)
        end
      end

      def reconcile_from_url(raw)
        url_components = parse_database_url(raw.url)
        return unless url_components

        # URL is the source of truth - populate all components from it
        raw.host = url_components[:host] if url_components[:host]
        raw.port = url_components[:port] if url_components[:port]
        raw.name = url_components[:name] if url_components[:name]
        raw.user = url_components[:user] if url_components[:user]
        raw.password = url_components[:password] if url_components[:password]
      end

      def reconcile_from_components(raw)
        name = raw.name
        has_name = name && !name.empty?

        # If no database config at all, that's fine - might not need database
        return unless has_name || has_any_database_component?(raw)

        # If name is missing, use the environment-based default name
        raw.name = "fact_db_#{environment}" unless has_name

        # Use defaults for host/port if not set
        raw.host = "localhost" if raw.host.nil? || raw.host.empty?
        raw.port = 5432 if raw.port.nil?

        # Build and set the URL
        raw.url = build_database_url(raw)
      end

      def has_any_database_component?(raw)
        [:host, :port, :user, :password].any? do |comp|
          val = raw.send(comp)
          next false if val.nil?
          next false if val.respond_to?(:empty?) && val.empty?
          # Skip defaults
          next false if comp == :host && val == "localhost"
          next false if comp == :port && val == 5432
          true
        end
      end

      def parse_database_url(url)
        return nil if url.nil? || url.empty?

        uri = URI.parse(url)
        return nil unless uri

        {
          host: uri.host,
          port: uri.port,
          name: uri.path&.sub(%r{^/}, ""),
          user: uri.user,
          password: uri.password
        }.compact
      rescue URI::InvalidURIError
        nil
      end

      def build_database_url(raw)
        return nil unless raw.name && !raw.name.empty?

        # Default to current OS user if no user specified
        user = raw.user
        user = ENV["USER"] if user.nil? || user.empty?

        auth = if user && !user.empty?
          if raw.password && !raw.password.empty?
            "#{user}:#{raw.password}@"
          else
            "#{user}@"
          end
        else
          ""
        end

        host = raw.host || "localhost"
        port = raw.port || 5432

        "postgresql://#{auth}#{host}:#{port}/#{raw.name}"
      end
    end
  end
end
