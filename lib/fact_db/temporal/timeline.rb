# frozen_string_literal: true

module FactDb
  module Temporal
    # Builds and analyzes temporal timelines of facts for an entity
    #
    # Provides methods to view an entity's history, group events by time periods,
    # find overlapping facts, and compare states at different points in time.
    # Includes Enumerable for easy iteration over timeline events.
    #
    # @example Build a timeline for an entity
    #   timeline = Timeline.new.build(entity_id: person.id)
    #   timeline.by_year.each { |year, events| puts "#{year}: #{events.count} events" }
    #
    # @example Find currently active facts
    #   active_facts = timeline.active
    #
    class Timeline
      include Enumerable

      # @return [Array<TimelineEvent>] the timeline events
      attr_reader :events

      # Initializes a new empty Timeline
      def initialize
        @events = []
      end

      # Iterates over timeline event hashes
      #
      # @yield [Hash] each event as a hash
      # @return [Enumerator] if no block given
      def each(&block)
        to_hash.each(&block)
      end

      # Builds a timeline of facts for an entity
      #
      # @param entity_id [Integer] the entity to build timeline for
      # @param from [Date, Time, nil] start of date range (optional)
      # @param to [Date, Time, nil] end of date range (optional)
      # @return [Timeline] self for method chaining
      def build(entity_id:, from: nil, to: nil)
        facts = fetch_facts(entity_id, from, to)
        @events = facts.map { |fact| TimelineEvent.new(fact) }
        self
      end

      # Returns events sorted by valid_at date
      #
      # @return [Array<TimelineEvent>] sorted events
      def to_a
        @events.sort_by(&:valid_at)
      end

      # Returns events as an array of hashes
      #
      # @return [Array<Hash>] events converted to hash format
      def to_hash
        to_a.map(&:to_hash)
      end

      # Groups events by year
      #
      # @return [Hash<Integer, Array<TimelineEvent>>] events grouped by year
      def by_year
        to_a.group_by { |event| event.valid_at.year }
      end

      # Groups events by month
      #
      # @return [Hash<String, Array<TimelineEvent>>] events grouped by "YYYY-MM" key
      def by_month
        to_a.group_by { |event| event.valid_at.strftime("%Y-%m") }
      end

      # Returns events in a specific date range
      #
      # @param from [Date, Time] start of range (inclusive)
      # @param to [Date, Time] end of range (inclusive)
      # @return [Array<TimelineEvent>] events within the range
      def between(from, to)
        to_a.select { |event| event.valid_at >= from && event.valid_at <= to }
      end

      # Returns currently active (valid) events
      #
      # @return [Array<TimelineEvent>] events with no invalid_at date
      def active
        to_a.select(&:currently_valid?)
      end

      # Returns historical (no longer valid) events
      #
      # @return [Array<TimelineEvent>] events that have been invalidated
      def historical
        to_a.reject(&:currently_valid?)
      end

      # Finds pairs of overlapping events
      #
      # Two events overlap if their validity periods intersect.
      #
      # @return [Array<Array<TimelineEvent, TimelineEvent>>] pairs of overlapping events
      def overlapping
        result = []
        sorted = to_a

        sorted.each_with_index do |event, i|
          sorted[(i + 1)..].each do |other|
            result << [event, other] if events_overlap?(event, other)
          end
        end

        result
      end

      # Returns the state (valid events) at a specific point in time
      #
      # @param date [Date, Time] the point in time to query
      # @return [Array<TimelineEvent>] events valid at the given date
      def state_at(date)
        to_a.select { |event| event.valid_at?(date) }
      end

      # Generates a summary of changes between consecutive events
      #
      # @return [Array<Hash>] array of hashes with :from, :to, and :gap_days keys
      def changes_summary
        sorted = to_a

        sorted.each_cons(2).map do |prev_event, next_event|
          {
            from: prev_event,
            to: next_event,
            gap_days: (next_event.valid_at.to_date - (prev_event.invalid_at || prev_event.valid_at).to_date).to_i
          }
        end
      end

      private

      def fetch_facts(entity_id, from, to)
        scope = Models::Fact.mentioning_entity(entity_id).order(valid_at: :asc)
        scope = scope.where("valid_at >= ?", from) if from
        scope = scope.where("valid_at <= ?", to) if to
        scope
      end

      def events_overlap?(event1, event2)
        return false if event1.invalid_at && event1.invalid_at <= event2.valid_at
        return false if event2.invalid_at && event2.invalid_at <= event1.valid_at

        true
      end
    end

    # Wraps a Fact as a timeline event with convenience methods
    #
    # Provides a simplified interface for timeline operations,
    # delegating most methods to the underlying fact.
    #
    class TimelineEvent
      # @return [FactDb::Models::Fact] the underlying fact
      attr_reader :fact

      # @!method id
      #   @return [Integer] the fact ID
      # @!method text
      #   @return [String] the fact text
      # @!method valid_at
      #   @return [Time] when the fact became valid
      # @!method invalid_at
      #   @return [Time, nil] when the fact became invalid
      # @!method status
      #   @return [String] the fact status
      # @!method currently_valid?
      #   @return [Boolean] true if fact is currently valid
      # @!method valid_at?(date)
      #   @param date [Date, Time] the point in time
      #   @return [Boolean] true if valid at the given date
      # @!method duration
      #   @return [ActiveSupport::Duration, nil] validity duration
      # @!method duration_days
      #   @return [Integer, nil] validity duration in days
      # @!method entities
      #   @return [Array<Entity>] mentioned entities
      # @!method source_contents
      #   @return [Array<Source>] source documents
      delegate :id, :text, :valid_at, :invalid_at, :status,
               :currently_valid?, :valid_at?, :duration, :duration_days,
               :entities, :source_contents, to: :fact

      # Initializes a new TimelineEvent
      #
      # @param fact [FactDb::Models::Fact] the fact to wrap
      def initialize(fact)
        @fact = fact
      end

      # Converts the event to a hash representation
      #
      # @return [Hash] hash with :id, :text, :valid_at, :invalid_at, :status, :duration_days, :entities
      def to_hash
        {
          id: id,
          text: text,
          valid_at: valid_at,
          invalid_at: invalid_at,
          status: status,
          duration_days: duration_days,
          entities: entities.map(&:name)
        }
      end

      # Compares events by valid_at date for sorting
      #
      # @param other [TimelineEvent] the event to compare with
      # @return [Integer] -1, 0, or 1
      def <=>(other)
        valid_at <=> other.valid_at
      end
    end
  end
end
