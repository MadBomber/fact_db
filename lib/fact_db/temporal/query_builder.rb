# frozen_string_literal: true

module FactDb
  module Temporal
    # A scoped query builder for temporal queries.
    # Allows chaining: facts.at("2024-01-15").query("Paula's role")
    #
    # @example Basic usage
    #   facts.at("2024-01-15").query("Paula's role", format: :cypher)
    #   facts.at("2024-01-15").facts_for(entity_id)
    #   facts.at("2024-01-15").compare_to("2024-06-15")
    #
    class QueryBuilder
      attr_reader :date

      # Initialize with a Facts instance and date
      #
      # @param facts [FactDb::Facts] The Facts instance
      # @param date [Date] The point in time
      def initialize(facts, date)
        @facts = facts
        @date = date
      end

      # Execute a query at this point in time
      #
      # @param topic [String] The query topic
      # @param format [Symbol] Output format (:json, :triples, :cypher, :text, :prolog)
      # @return [Array, String, Hash] Results at this point in time
      def query(topic, format: :json, **options)
        @facts.query_facts(topic: topic, at: @date, format: format, **options)
      end

      # Get all facts valid at this date
      #
      # @param format [Symbol] Output format
      # @return [Array, String, Hash] Results
      def facts(format: :json, **options)
        @facts.facts_at(@date, format: format, **options)
      end

      # Get facts for a specific entity at this date
      #
      # @param entity_id [Integer] Entity ID
      # @param format [Symbol] Output format
      # @return [Array, String, Hash] Results
      def facts_for(entity_id, format: :json, **options)
        @facts.facts_at(@date, entity: entity_id, format: format, **options)
      end

      # Compare this date to another
      #
      # @param other_date [Date, String] The date to compare to
      # @param topic [String, nil] Optional topic to compare
      # @return [Hash] Differences with :added, :removed, :unchanged keys
      def compare_to(other_date, topic: nil)
        @facts.diff(topic, from: @date, to: other_date)
      end

      # Get the timeline state at this date
      #
      # @param entity_id [Integer] Entity ID
      # @return [Array] Facts valid at this date for the entity
      def state_for(entity_id, format: :json)
        @facts.facts_at(@date, entity: entity_id, format: format)
      end
    end
  end
end
