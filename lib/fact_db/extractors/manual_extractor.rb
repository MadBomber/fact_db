# frozen_string_literal: true

module FactDb
  module Extractors
    # Manual fact extractor for API-driven fact creation
    #
    # Passes through user-provided text as a single fact without any
    # automated extraction. Used when the user provides fact text and
    # metadata directly via the API.
    #
    # @example Extract a manual fact
    #   extractor = ManualExtractor.new
    #   facts = extractor.extract("John works at Acme", valid_at: Date.today)
    #
    class ManualExtractor < Base
      # Extracts a single fact from the provided text
      #
      # Returns the text as-is without parsing. All metadata comes from context.
      #
      # @param text [String] the fact text
      # @param context [Hash] fact metadata
      # @option context [Date, Time] :valid_at when the fact became valid
      # @option context [Date, Time] :invalid_at when the fact became invalid
      # @option context [Array<Hash>] :mentions entity mentions
      # @option context [Float] :confidence confidence score
      # @option context [Hash] :metadata additional metadata
      # @return [Array<Hash>] array with single fact hash, or empty if text is blank
      def extract(text, context = {})
        return [] if text.nil? || text.strip.empty?

        valid_at = context[:valid_at] || context[:captured_at] || Time.current

        [
          build_fact(
            text: text,
            valid_at: valid_at,
            invalid_at: context[:invalid_at],
            mentions: context[:mentions] || [],
            confidence: context[:confidence] || 1.0,
            metadata: context[:metadata] || {}
          )
        ]
      end

      # Returns empty array since manual extraction expects entities to be provided
      #
      # @param text [String] ignored
      # @return [Array] empty array
      def extract_entities(text)
        []
      end

      # Creates a single fact with full control over all attributes
      #
      # Convenience method that wraps #extract with named parameters.
      #
      # @param text [String] the fact text
      # @param valid_at [Date, Time] when the fact became valid
      # @param invalid_at [Date, Time, nil] when the fact became invalid
      # @param mentions [Array<Hash>] entity mentions
      # @param confidence [Float] confidence score (0.0 to 1.0)
      # @param metadata [Hash] additional metadata
      # @return [Hash] the fact hash
      def create_fact(text:, valid_at:, invalid_at: nil, mentions: [], confidence: 1.0, metadata: {})
        extract(text, {
          valid_at: valid_at,
          invalid_at: invalid_at,
          mentions: mentions,
          confidence: confidence,
          metadata: metadata
        }).first
      end

      # Creates an entity hash
      #
      # Convenience method for building entity data manually.
      #
      # @param name [String] the entity name
      # @param type [String, Symbol] entity kind (person, organization, etc.)
      # @param aliases [Array<String>] alternative names
      # @param attributes [Hash] additional attributes
      # @return [Hash] the entity hash
      def create_entity(name:, type:, aliases: [], attributes: {})
        build_entity(
          name: name,
          type: type,
          aliases: aliases,
          attributes: attributes
        )
      end
    end
  end
end
