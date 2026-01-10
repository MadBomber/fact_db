# frozen_string_literal: true

require "json"

module FactDb
  module Extractors
    class LLMExtractor < Base
      FACT_EXTRACTION_PROMPT = <<~PROMPT
        Extract ATOMIC factual assertions from the following text. Break compound
        statements into individual, indivisible facts - one assertion per fact.

        For each atomic fact:
        1. State a single, indivisible assertion (not multiple facts combined)
        2. Identify when it became true (valid_at) if mentioned or inferable
        3. Identify when it stopped being true (invalid_at) if mentioned
        4. Identify entities mentioned (people, organizations, places, products)
        5. Assign a confidence score (0.0 to 1.0) based on how explicitly stated the fact is
        6. For each entity, include any aliases or alternative names used in the text

        Text:
        %<text>s

        Return as a JSON array with this structure:
        [
          {
            "text": "Paula works at Microsoft",
            "valid_at": "2024-01-10",
            "invalid_at": null,
            "confidence": 0.95,
            "mentions": [
              {"name": "Paula Chen", "type": "person", "role": "subject", "aliases": ["Paula", "P. Chen"]},
              {"name": "Microsoft", "type": "organization", "role": "object", "aliases": ["MS", "Microsoft Corporation"]}
            ]
          },
          {
            "text": "Paula holds the title of Principal Engineer",
            "valid_at": "2024-01-10",
            "invalid_at": null,
            "confidence": 0.95,
            "mentions": [
              {"name": "Paula Chen", "type": "person", "role": "subject", "aliases": ["Paula", "P. Chen"]}
            ]
          }
        ]

        Rules:
        - ATOMIC FACTS: Break compound statements into smallest meaningful assertions
          - "John and Mary married in Paris" becomes TWO facts: "John married Mary" AND "The marriage took place in Paris"
          - "She is a doctor at City Hospital" becomes TWO facts: "She is a doctor" AND "She works at City Hospital"
        - Extract only factual assertions, not opinions or speculation
        - Use ISO 8601 date format (YYYY-MM-DD) when possible
        - Set invalid_at to null if the fact is still true or unknown
        - Set valid_at to null if the timing is not mentioned
        - Entity types: person, organization, place, product, event, concept
        - Roles: subject, object, location, temporal, instrument, beneficiary
        - For person entities, use the most complete/formal name as "name" and shorter/alternative forms as "aliases"
        - Common aliases include: nicknames, titles with name, name variations, abbreviations
        - NEVER include pronouns as aliases (he, she, him, her, they, them, his, her, their, it, we, you, I, me, my, etc.)
        - NEVER include generic terms as aliases (man, woman, person, husband, wife, the man, this person, etc.)
        - Only include proper names, nicknames, and formal variations as aliases

        Return only valid JSON, no additional text.
      PROMPT

      ENTITY_EXTRACTION_PROMPT = <<~PROMPT
        Extract all named entities from the following text.
        For each entity:
        1. Identify the canonical name
        2. Classify the type (person, organization, place, product, event, concept)
        3. List any aliases or alternative names mentioned

        Text:
        %<text>s

        Return as a JSON array:
        [
          {
            "name": "Paula Chen",
            "type": "person",
            "aliases": ["Paula", "P. Chen"]
          }
        ]

        Important rules for aliases:
        - NEVER include pronouns (he, she, him, her, they, them, his, her, their, it, we, you, I, me, my, etc.)
        - NEVER include generic terms (man, woman, person, husband, wife, the man, this person, believers, disciples, etc.)
        - Only include proper names, nicknames, titles, and formal name variations

        Return only valid JSON, no additional text.
      PROMPT

      def extract(text, context = {})
        return [] if text.nil? || text.strip.empty?

        client = config.llm_client
        raise ConfigurationError, "LLM client not configured" unless client

        prompt = format(FACT_EXTRACTION_PROMPT, text: text)
        response = call_llm(client, prompt)

        parse_fact_response(response, context)
      end

      def extract_entities(text)
        return [] if text.nil? || text.strip.empty?

        client = config.llm_client
        raise ConfigurationError, "LLM client not configured" unless client

        prompt = format(ENTITY_EXTRACTION_PROMPT, text: text)
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
            type: entity_data["type"] || "concept",
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
            type: mention["type"] || "concept",
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
