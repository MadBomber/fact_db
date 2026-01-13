# frozen_string_literal: true

module FactDb
  module Extractors
    # Abstract base class for fact extractors
    #
    # Provides common interface and helper methods for extracting facts and entities
    # from text. Subclasses must implement #extract and #extract_entities.
    #
    # @abstract Subclass and override {#extract} and {#extract_entities} to implement.
    #
    # @example Create a custom extractor
    #   class MyExtractor < FactDb::Extractors::Base
    #     def extract(text, context = {})
    #       # Implementation
    #     end
    #
    #     def extract_entities(text)
    #       # Implementation
    #     end
    #   end
    #
    class Base
      # @return [FactDb::Config] the configuration object
      attr_reader :config

      # Initializes a new extractor
      #
      # @param config [FactDb::Config] configuration object (defaults to FactDb.config)
      def initialize(config = FactDb.config)
        @config = config
      end

      # Extracts facts from text
      #
      # @abstract Subclass and override this method
      # @param text [String] raw text to extract from
      # @param context [Hash] additional context (captured_at, source_uri, etc.)
      # @return [Array<Hash>] array of fact data hashes
      # @raise [NotImplementedError] if not implemented by subclass
      def extract(text, context = {})
        raise NotImplementedError, "#{self.class} must implement #extract"
      end

      # Extracts entities from text
      #
      # @abstract Subclass and override this method
      # @param text [String] raw text to extract from
      # @return [Array<Hash>] array of entity hashes with :name, :kind, :aliases
      # @raise [NotImplementedError] if not implemented by subclass
      def extract_entities(text)
        raise NotImplementedError, "#{self.class} must implement #extract_entities"
      end

      # Returns the extraction method name derived from class name
      #
      # @return [String] method name (e.g., "manual", "llm", "rule_based")
      def extraction_method
        self.class.name.split("::").last.sub("Extractor", "").underscore
      end

      class << self
        # Factory method to create an extractor by type
        #
        # @param type [Symbol, String] extractor type (:manual, :llm, :rule_based)
        # @param config [FactDb::Config] configuration object
        # @return [Base] an extractor instance
        # @raise [ArgumentError] if type is unknown
        #
        # @example
        #   extractor = FactDb::Extractors::Base.for(:llm)
        def for(type, config = FactDb.config)
          case type.to_sym
          when :manual
            ManualExtractor.new(config)
          when :llm
            LLMExtractor.new(config)
          when :rule_based
            RuleBasedExtractor.new(config)
          else
            raise ArgumentError, "Unknown extractor type: #{type}"
          end
        end

        # Returns list of available extractor types
        #
        # @return [Array<Symbol>] available extractor type symbols
        def available_types
          %i[manual llm rule_based]
        end
      end

      protected

      # Parses a date string, returning nil if invalid
      #
      # Supports natural language parsing via Chronic if available.
      #
      # @param date_str [String, nil] date string to parse
      # @return [Date, nil] parsed date or nil if invalid
      def parse_date(date_str)
        return nil if date_str.nil? || date_str.to_s.empty?

        # Try chronic for natural language dates
        if defined?(Chronic)
          chronic_result = Chronic.parse(date_str)
          return chronic_result.to_date if chronic_result
        end

        Date.parse(date_str.to_s)
      rescue Date::Error, ArgumentError
        nil
      end

      # Parses a timestamp string, returning nil if invalid
      #
      # Supports natural language parsing via Chronic if available.
      #
      # @param timestamp_str [String, nil] timestamp string to parse
      # @return [Time, nil] parsed time or nil if invalid
      def parse_timestamp(timestamp_str)
        return nil if timestamp_str.nil? || timestamp_str.to_s.empty?

        # Try chronic for natural language dates
        if defined?(Chronic)
          chronic_result = Chronic.parse(timestamp_str)
          return chronic_result if chronic_result
        end

        Time.parse(timestamp_str.to_s)
      rescue ArgumentError
        nil
      end

      # Builds a standardized fact hash
      #
      # @param text [String] the fact text
      # @param valid_at [Date, Time] when the fact became valid
      # @param invalid_at [Date, Time, nil] when the fact became invalid
      # @param mentions [Array<Hash>] entity mentions
      # @param confidence [Float] confidence score (0.0 to 1.0)
      # @param metadata [Hash] additional metadata
      # @return [Hash] standardized fact hash for persistence
      def build_fact(text:, valid_at:, invalid_at: nil, mentions: [], confidence: 1.0, metadata: {})
        {
          text: text.strip,
          valid_at: valid_at,
          invalid_at: invalid_at,
          mentions: mentions,
          confidence: confidence,
          metadata: metadata,
          extraction_method: extraction_method
        }
      end

      # Builds a standardized entity hash
      #
      # Automatically filters aliases through AliasFilter.
      #
      # @param name [String] the entity name
      # @param kind [String, Symbol] entity kind (person, organization, etc.)
      # @param aliases [Array<String>] alternative names
      # @param attributes [Hash] additional attributes
      # @return [Hash] standardized entity hash
      def build_entity(name:, kind:, aliases: [], attributes: {})
        canonical_name = name.strip
        filtered_aliases = Validation::AliasFilter.filter(aliases, name: canonical_name)

        {
          name: canonical_name,
          kind: kind.to_s,
          aliases: filtered_aliases,
          attributes: attributes
        }
      end

      # Builds a standardized entity mention hash
      #
      # Automatically filters aliases through AliasFilter.
      #
      # @param name [String] the entity name
      # @param kind [String, Symbol] entity kind
      # @param role [String, Symbol, nil] mention role (subject, object, etc.)
      # @param confidence [Float] confidence score (0.0 to 1.0)
      # @param aliases [Array<String>] alternative names
      # @return [Hash] standardized mention hash
      def build_mention(name:, kind:, role: nil, confidence: 1.0, aliases: [])
        canonical_name = name.strip
        raw_aliases = Array(aliases).map { |a| a.to_s.strip }.reject(&:empty?)
        filtered_aliases = Validation::AliasFilter.filter(raw_aliases, name: canonical_name)

        {
          name: canonical_name,
          kind: kind.to_s,
          role: role&.to_s,
          confidence: confidence,
          aliases: filtered_aliases
        }
      end
    end
  end
end
