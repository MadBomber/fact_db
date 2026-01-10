# frozen_string_literal: true

require "uri"

module FactDb
  class Config
    module Database
      # ==========================================================================
      # Database Component Accessors
      # ==========================================================================
      #
      # These methods provide convenient access to database components.
      # Components are automatically reconciled at config load time:
      #   - If database.url exists: components are extracted and populated
      #   - If database.url is missing: it's built from components
      #
      # ==========================================================================

      # @return [String, nil] the database URL
      def database_url
        url = database&.url
        return url if url && !url.empty?

        build_database_url
      end

      # @return [String, nil] the database host
      def database_host
        database&.host
      end

      # @return [Integer, nil] the database port
      def database_port
        database&.port
      end

      # @return [String, nil] the database name
      def database_name
        database&.name
      end

      # @return [String, nil] the database user
      def database_user
        database&.user
      end

      # @return [String, nil] the database password
      def database_password
        database&.password
      end

      # @return [Integer] the database connection pool size
      def database_pool_size
        database&.pool_size.to_i
      end

      # @return [Integer] the database connection timeout
      def database_timeout
        database&.timeout.to_i
      end

      # Build a hash suitable for ActiveRecord.establish_connection
      #
      # @return [Hash] database configuration hash
      def database_config
        url = database_url
        return {} unless url

        uri = URI.parse(url)

        {
          adapter: "postgresql",
          host: uri.host,
          port: uri.port || 5432,
          database: uri.path&.sub(%r{^/}, ""),
          username: uri.user,
          password: uri.password,
          pool: database_pool_size,
          timeout: database_timeout,
          encoding: "unicode",
          prepared_statements: false,
          advisory_locks: false
        }.compact
      end

      # Check if database is configured
      #
      # @return [Boolean] true if database URL or name is configured
      def database_configured?
        url = database&.url
        (url && !url.empty?) || (database&.name && !database.name.empty?)
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

      # Parse database URL into component hash
      #
      # @return [Hash, nil] parsed components or nil if no URL
      def parse_database_url
        url = database&.url
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

      private

      # Build a database URL from components
      #
      # @return [String, nil] the database URL or nil if name not configured
      def build_database_url
        return nil unless database&.name && !database.name.empty?

        # Default to current OS user if no user specified
        user = database.user
        user = ENV["USER"] if user.nil? || user.empty?

        auth = if user && !user.empty?
          if database.password && !database.password.empty?
            "#{user}:#{database.password}@"
          else
            "#{user}@"
          end
        else
          ""
        end

        host = database.host || "localhost"
        port = database.port || 5432

        "postgresql://#{auth}#{host}:#{port}/#{database.name}"
      end

      # ==========================================================================
      # Database Configuration Reconciliation
      # ==========================================================================
      #
      # Ensures database.url and database.* components are synchronized:
      #
      # 1. If database.url exists:
      #    - Extract all components from the URL
      #    - Populate missing component fields from URL
      #
      # 2. If database.url is missing but components exist:
      #    - Verify minimum required components (at least database.name)
      #    - Build and set database.url from components
      #
      # This runs automatically at config load time via on_load callback.
      #
      # ==========================================================================

      def reconcile_database_config
        url = database&.url
        has_url = url && !url.empty?

        if has_url
          reconcile_from_url
        else
          reconcile_from_components
        end
      end

      def reconcile_from_url
        url_components = parse_database_url
        return unless url_components

        # URL is the source of truth - populate all components from it
        %i[host port name user password].each do |component|
          url_value = url_components[component]
          next if url_value.nil?

          database.send("#{component}=", url_value)
        end
      end

      def reconcile_from_components
        # Check what components we have
        name = database&.name
        has_name = name && !name.empty?

        # If no database config at all, that's fine - might not need database
        # Just return without error; validate_database! will catch if needed later
        return unless has_name || has_any_database_component?

        # If name is missing, use the environment-based default name
        unless has_name
          database.name = "fact_db_#{environment}"
        end

        # Use defaults for host/port if not set
        database.host = "localhost" if database.host.nil? || database.host.empty?
        database.port = 5432 if database.port.nil?

        # Build and set the URL
        database.url = build_database_url
      end

      def has_any_database_component?
        %i[host port user password].any? do |comp|
          val = database&.send(comp)
          next false if val.nil?
          next false if val.respond_to?(:empty?) && val.empty?
          # Skip defaults
          next false if comp == :host && val == "localhost"
          next false if comp == :port && val == 5432
          true
        end
      end
    end
  end
end
