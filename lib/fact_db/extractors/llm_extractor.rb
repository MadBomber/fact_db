# frozen_string_literal: true

require "json"

module FactDb
  module Extractors
    # LLM-based fact extractor using language models
    #
    # Uses a configured LLM client to extract atomic facts and entities from
    # unstructured text. Parses JSON responses from the LLM and builds
    # standardized fact/entity hashes.
    #
    # @example Extract facts using LLM
    #   FactDb.configure { |c| c.llm_client = MyLLMClient.new }
    #   extractor = LLMExtractor.new
    #   facts = extractor.extract("Paula joined Microsoft on January 10, 2024...")
    #
    class LLMExtractor < Base
      # Extracts atomic facts from text using the configured LLM
      #
      # Prompts the LLM to identify factual assertions, temporal information,
      # entity mentions with roles, and confidence scores.
      #
      # @param text [String] raw text to extract from
      # @param context [Hash] additional context
      # @option context [Date, Time] :captured_at default timestamp for facts
      # @return [Array<Hash>] array of fact hashes
      # @raise [ConfigurationError] if no LLM client is configured
      def extract(text, context = {})
        return [] if text.nil? || text.strip.empty?

        client = config.llm_client
        raise ConfigurationError, "LLM client not configured" unless client

        prompt = format(config.prompts.fact_extraction, text: text)
        response = call_llm(client, prompt)

        parse_fact_response(response, context)
      end

      # Extracts entities from text using the configured LLM
      #
      # Prompts the LLM to identify named entities, classify their types,
      # and list any aliases or alternative names.
      #
      # @param text [String] raw text to extract from
      # @return [Array<Hash>] array of entity hashes with :name, :kind, :aliases
      # @raise [ConfigurationError] if no LLM client is configured
      def extract_entities(text)
        return [] if text.nil? || text.strip.empty?

        client = config.llm_client
        raise ConfigurationError, "LLM client not configured" unless client

        prompt = format(config.prompts.entity_extraction, text: text)
        response = call_llm(client, prompt)

        parse_entity_response(response)
      end

      private

      def call_llm(client, prompt)
        # Support multiple LLM client interfaces
        if client.respond_to?(:chat)
          # Standard chat interface (most LLM gems)
          client.chat(prompt)
        elsif client.respond_to?(:complete)
          # Completion interface
          client.complete(prompt)
        elsif client.respond_to?(:call)
          # Callable/lambda interface
          client.call(prompt)
        else
          raise ConfigurationError, "LLM client must respond to :chat, :complete, or :call"
        end
      end

      def parse_fact_response(response, context)
        json = extract_json(response)
        parsed = JSON.parse(json)

        parsed.map do |fact_data|
          valid_at = parse_timestamp(fact_data["valid_at"]) ||
                     context[:captured_at] ||
                     Time.current

          build_fact(
            text: fact_data["text"],
            valid_at: valid_at,
            invalid_at: parse_timestamp(fact_data["invalid_at"]),
            mentions: parse_mentions(fact_data["mentions"]),
            confidence: fact_data["confidence"]&.to_f || 0.8,
            metadata: { llm_response: fact_data }
          )
        end
      rescue JSON::ParserError => e
        config.logger&.warn("Failed to parse LLM fact response: #{e.message}")
        []
      end

      def parse_entity_response(response)
        json = extract_json(response)
        parsed = JSON.parse(json)

        parsed.map do |entity_data|
          build_entity(
            name: entity_data["name"],
            kind: entity_data["type"] || "concept",
            aliases: entity_data["aliases"] || [],
            attributes: entity_data["attributes"] || {}
          )
        end
      rescue JSON::ParserError => e
        config.logger&.warn("Failed to parse LLM entity response: #{e.message}")
        []
      end

      def parse_mentions(mentions_data)
        return [] unless mentions_data.is_a?(Array)

        mentions_data.map do |mention|
          build_mention(
            name: mention["name"],
            kind: mention["type"] || "concept",
            role: mention["role"],
            confidence: mention["confidence"]&.to_f || 1.0,
            aliases: mention["aliases"] || []
          )
        end
      end

      def extract_json(response)
        # Handle responses that may have markdown code blocks
        text = response.to_s.strip

        # Remove markdown code blocks if present
        if text.start_with?("```")
          text = text.sub(/\A```(?:json)?\n?/, "").sub(/\n?```\z/, "")
        end

        # Find JSON array in response
        if (match = text.match(/\[[\s\S]*\]/))
          match[0]
        else
          text
        end
      end
    end
  end
end
