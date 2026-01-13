# frozen_string_literal: true

module FactDb
  module Temporal
    # Executes temporal queries on facts with time-based filtering
    #
    # Provides methods for querying facts at specific points in time,
    # comparing states between dates, and searching with temporal constraints.
    #
    # @example Query current facts about an entity
    #   query = Query.new
    #   facts = query.current_facts(entity_id: person.id)
    #
    # @example Compare facts at two points in time
    #   diff = query.diff(entity_id: person.id, from_date: Date.parse("2023-01-01"), to_date: Date.today)
    #   puts "Added: #{diff[:added].count}, Removed: #{diff[:removed].count}"
    #
    class Query
      # @return [ActiveRecord::Relation] the base scope for queries
      attr_reader :scope

      # Initializes a new Query with an optional base scope
      #
      # @param scope [ActiveRecord::Relation] base fact scope (defaults to all facts)
      def initialize(scope = Models::Fact.all)
        @scope = scope
      end

      # Executes a temporal query with multiple filters
      #
      # @param topic [String, nil] text to search for in fact content
      # @param at [Date, Time, nil] point in time (nil for currently valid)
      # @param entity_id [Integer, nil] filter by entity
      # @param status [Symbol] fact status filter (:canonical, :superseded, :synthesized, :all)
      # @param limit [Integer, nil] maximum number of results
      # @return [ActiveRecord::Relation] matching facts ordered by valid_at desc
      def execute(topic: nil, at: nil, entity_id: nil, status: :canonical, limit: nil)
        result = @scope

        # Status filtering
        result = apply_status_filter(result, status)

        # Temporal filtering
        result = apply_temporal_filter(result, at)

        # Entity filtering
        result = apply_entity_filter(result, entity_id)

        # Topic search
        result = apply_topic_search(result, topic)

        # Ordering - most recently valid first
        result = result.order(valid_at: :desc)

        # Limit results
        result = result.limit(limit) if limit

        result
      end

      # Returns currently valid canonical facts about an entity
      #
      # @param entity_id [Integer] the entity to query
      # @return [ActiveRecord::Relation] currently valid facts mentioning the entity
      def current_facts(entity_id:)
        execute(entity_id: entity_id, at: nil, status: :canonical)
      end

      # Returns facts valid at a specific point in time
      #
      # @param date [Date, Time] the point in time to query
      # @param entity_id [Integer, nil] optional entity filter
      # @return [ActiveRecord::Relation] facts valid at the given date
      def facts_at(date, entity_id: nil)
        execute(at: date, entity_id: entity_id, status: :canonical)
      end

      # Returns facts that became valid within a date range
      #
      # @param from [Date, Time] start of range (inclusive)
      # @param to [Date, Time] end of range (inclusive)
      # @param entity_id [Integer, nil] optional entity filter
      # @return [ActiveRecord::Relation] facts created in the range, ordered by valid_at asc
      def facts_created_between(from:, to:, entity_id: nil)
        result = @scope.canonical.became_valid_between(from, to)
        result = result.mentioning_entity(entity_id) if entity_id
        result.order(valid_at: :asc)
      end

      # Returns facts that became invalid within a date range
      #
      # @param from [Date, Time] start of range (inclusive)
      # @param to [Date, Time] end of range (inclusive)
      # @param entity_id [Integer, nil] optional entity filter
      # @return [ActiveRecord::Relation] facts invalidated in the range, ordered by invalid_at asc
      def facts_invalidated_between(from:, to:, entity_id: nil)
        result = @scope.became_invalid_between(from, to)
        result = result.mentioning_entity(entity_id) if entity_id
        result.order(invalid_at: :asc)
      end

      # Searches facts by text with temporal filtering
      #
      # Uses PostgreSQL full-text search with optional point-in-time filtering.
      #
      # @param query [String] text to search for
      # @param at [Date, Time, nil] point in time (nil for currently valid)
      # @param entity_id [Integer, nil] optional entity filter
      # @param limit [Integer] maximum number of results (default: 20)
      # @return [ActiveRecord::Relation] matching facts
      def semantic_search(query:, at: nil, entity_id: nil, limit: 20)
        result = @scope.canonical.search_text(query)
        result = apply_temporal_filter(result, at)
        result = result.mentioning_entity(entity_id) if entity_id
        result.limit(limit)
      end

      # Returns facts where an entity has a specific mention role
      #
      # @param entity_id [Integer] the entity to query
      # @param role [String, Symbol] the mention role (e.g., :subject, :object)
      # @param at [Date, Time, nil] point in time (nil for currently valid)
      # @return [ActiveRecord::Relation] facts with the entity in the specified role
      def facts_with_entity_role(entity_id:, role:, at: nil)
        result = @scope.canonical.with_role(entity_id, role)
        result = apply_temporal_filter(result, at)
        result.order(valid_at: :desc)
      end

      # Compares facts at two points in time to find changes
      #
      # @param entity_id [Integer] the entity to compare
      # @param from_date [Date, Time] the earlier point in time
      # @param to_date [Date, Time] the later point in time
      # @return [Hash] hash with :added, :removed, and :unchanged arrays of facts
      #
      # @example
      #   diff = query.diff(entity_id: 1, from_date: 1.year.ago, to_date: Date.today)
      #   puts "#{diff[:added].count} new facts, #{diff[:removed].count} removed"
      def diff(entity_id:, from_date:, to_date:)
        facts_at_from = facts_at(from_date, entity_id: entity_id).to_a
        facts_at_to = facts_at(to_date, entity_id: entity_id).to_a

        {
          added: facts_at_to - facts_at_from,
          removed: facts_at_from - facts_at_to,
          unchanged: facts_at_from & facts_at_to
        }
      end

      private

      def apply_status_filter(scope, status)
        case status.to_sym
        when :canonical
          scope.canonical
        when :superseded
          scope.superseded
        when :synthesized
          scope.synthesized
        when :all
          scope
        else
          scope.where(status: status.to_s)
        end
      end

      def apply_temporal_filter(scope, at)
        if at.nil?
          scope.currently_valid
        else
          scope.valid_at(at)
        end
      end

      def apply_entity_filter(scope, entity_id)
        return scope if entity_id.nil?

        scope.mentioning_entity(entity_id)
      end

      def apply_topic_search(scope, topic)
        return scope if topic.nil? || topic.empty?

        scope.search_text(topic)
      end
    end
  end
end
