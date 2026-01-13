# frozen_string_literal: true

module FactDb
  module Resolution
    # Handles fact lifecycle operations including supersession, synthesis, and conflict resolution
    #
    # Provides methods for managing fact relationships: superseding outdated facts,
    # synthesizing new facts from multiple sources, handling corroboration,
    # and detecting/resolving conflicts.
    #
    # @example Supersede an outdated fact
    #   resolver = FactResolver.new
    #   new_fact = resolver.supersede(old_fact.id, "Updated information", valid_at: Date.today)
    #
    class FactResolver
      # @return [FactDb::Config] the configuration object
      attr_reader :config

      # Initializes a new FactResolver instance
      #
      # @param config [FactDb::Config] configuration object (defaults to FactDb.config)
      def initialize(config = FactDb.config)
        @config = config
      end

      # Supersedes an existing fact with a new one
      #
      # Creates a new canonical fact and marks the old one as superseded.
      # Copies mentions and sources from the old fact unless new mentions are provided.
      #
      # @param old_fact_id [Integer] ID of the fact to supersede
      # @param new_text [String] the updated fact text
      # @param valid_at [Date, Time] when the new fact became valid
      # @param mentions [Array<Hash>] optional entity mentions for the new fact
      # @return [FactDb::Models::Fact] the new canonical fact
      # @raise [ResolutionError] if the fact is already superseded
      #
      # @example Supersede with new mentions
      #   resolver.supersede(fact.id, "John now works at NewCo",
      #     valid_at: Date.today,
      #     mentions: [{ entity_id: john.id, text: "John", role: :subject }])
      def supersede(old_fact_id, new_text, valid_at:, mentions: [])
        old_fact = Models::Fact.find(old_fact_id)

        raise ResolutionError, "Cannot supersede already superseded fact" if old_fact.superseded?

        Models::Fact.transaction do
          new_fact = Models::Fact.create!(
            text: new_text,
            valid_at: valid_at,
            status: "canonical",
            extraction_method: old_fact.extraction_method,
            confidence: old_fact.confidence
          )

          # Copy mentions from old fact if not provided
          if mentions.empty?
            old_fact.entity_mentions.each do |mention|
              new_fact.add_mention(
                entity: mention.entity,
                text: mention.mention_text,
                role: mention.mention_role,
                confidence: mention.confidence
              )
            end
          else
            mentions.each do |mention|
              entity = mention[:entity] || Models::Entity.find(mention[:entity_id])
              new_fact.add_mention(
                entity: entity,
                text: mention[:text],
                role: mention[:role],
                confidence: mention[:confidence] || 1.0
              )
            end
          end

          # Copy sources from old fact
          old_fact.fact_sources.each do |source|
            new_fact.add_source(
              source: source.source,
              kind: source.kind,
              excerpt: source.excerpt,
              confidence: source.confidence
            )
          end

          # Mark old fact as superseded
          old_fact.update!(
            status: "superseded",
            superseded_by_id: new_fact.id,
            invalid_at: valid_at
          )

          new_fact
        end
      end

      # Synthesizes a new fact from multiple source facts
      #
      # Creates a single synthesized fact that aggregates information from multiple facts.
      # Automatically aggregates entity mentions and links to all source content.
      #
      # @param source_fact_ids [Array<Integer>] IDs of the source facts
      # @param synthesized_text [String] the synthesized summary text
      # @param valid_at [Date, Time] when the synthesis is valid from
      # @param invalid_at [Date, Time, nil] when the synthesis becomes invalid
      # @param mentions [Array<Hash>] optional entity mentions (aggregated from sources if empty)
      # @return [FactDb::Models::Fact] the synthesized fact
      # @raise [ResolutionError] if no source facts are found
      #
      # @example Synthesize multiple facts
      #   resolver.synthesize([fact1.id, fact2.id], "Summary of events", valid_at: Date.today)
      def synthesize(source_fact_ids, synthesized_text, valid_at:, invalid_at: nil, mentions: [])
        source_facts = Models::Fact.where(id: source_fact_ids)

        raise ResolutionError, "No source facts found" if source_facts.empty?

        Models::Fact.transaction do
          synthesized = Models::Fact.create!(
            text: synthesized_text,
            valid_at: valid_at,
            invalid_at: invalid_at,
            status: "synthesized",
            derived_from_ids: source_fact_ids,
            extraction_method: "synthesized",
            confidence: calculate_synthesized_confidence(source_facts)
          )

          # Aggregate entity mentions from source facts if not provided
          if mentions.empty?
            aggregate_mentions(source_facts).each do |mention|
              synthesized.add_mention(**mention)
            end
          else
            mentions.each do |mention|
              entity = mention[:entity] || Models::Entity.find(mention[:entity_id])
              synthesized.add_mention(
                entity: entity,
                text: mention[:text],
                role: mention[:role],
                confidence: mention[:confidence] || 1.0
              )
            end
          end

          # Link all source content
          source_facts.each do |source_fact|
            source_fact.fact_sources.each do |source|
              synthesized.add_source(
                content: source.content,
                type: "supporting",
                excerpt: source.excerpt,
                confidence: source.confidence
              )
            end
          end

          synthesized
        end
      end

      # Marks a fact as corroborated by another fact
      #
      # Adds the corroborating fact ID to the corroborated_by_ids array.
      # If 2+ facts corroborate, status changes to "corroborated".
      #
      # @param fact_id [Integer] ID of the fact being corroborated
      # @param corroborating_fact_id [Integer] ID of the supporting fact
      # @return [FactDb::Models::Fact] the updated fact
      # @raise [ResolutionError] if attempting to corroborate with the same fact
      def corroborate(fact_id, corroborating_fact_id)
        fact = Models::Fact.find(fact_id)
        _corroborating = Models::Fact.find(corroborating_fact_id)

        raise ResolutionError, "Cannot corroborate with same fact" if fact_id == corroborating_fact_id

        fact.update!(
          corroborated_by_ids: (fact.corroborated_by_ids + [corroborating_fact_id]).uniq
        )

        # Optionally update status to corroborated if it was just canonical
        fact.update!(status: "corroborated") if fact.status == "canonical" && fact.corroborated_by_ids.size >= 2

        fact
      end

      # Invalidates a fact without replacement
      #
      # @param fact_id [Integer] ID of the fact to invalidate
      # @param at [Time] when the fact became invalid (defaults to now)
      # @return [FactDb::Models::Fact] the invalidated fact
      def invalidate(fact_id, at: Time.current)
        fact = Models::Fact.find(fact_id)
        fact.update!(invalid_at: at)
        fact
      end

      # Finds potentially conflicting facts
      #
      # Identifies facts with similar text (50-95% similarity) that might be contradictory.
      #
      # @param entity_id [Integer, nil] entity ID to filter by
      # @param topic [String, nil] topic to search for
      # @return [Array<Hash>] array of hashes with :fact1, :fact2, :similarity keys
      def find_conflicts(entity_id: nil, topic: nil)
        scope = Models::Fact.canonical.currently_valid

        if entity_id
          scope = scope.mentioning_entity(entity_id)
        end

        if topic
          scope = scope.search_text(topic)
        end

        # Group facts that might be about the same thing
        facts = scope.to_a
        conflicts = []

        facts.each_with_index do |fact, i|
          facts[(i + 1)..].each do |other|
            similarity = text_similarity(fact.text, other.text)
            if similarity > 0.5 && similarity < 0.95
              conflicts << {
                fact1: fact,
                fact2: other,
                similarity: similarity
              }
            end
          end
        end

        conflicts.sort_by { |c| -c[:similarity] }
      end

      # Resolves conflicts by keeping one fact and superseding others
      #
      # @param keep_fact_id [Integer] ID of the fact to keep as canonical
      # @param supersede_fact_ids [Array<Integer>] IDs of facts to mark as superseded
      # @param reason [String, nil] reason for the resolution (stored in metadata)
      # @return [FactDb::Models::Fact] the kept fact
      def resolve_conflict(keep_fact_id, supersede_fact_ids, reason: nil)
        Models::Fact.transaction do
          supersede_fact_ids.each do |fact_id|
            fact = Models::Fact.find(fact_id)
            fact.update!(
              status: "superseded",
              superseded_by_id: keep_fact_id,
              invalid_at: Time.current,
              metadata: fact.metadata.merge(supersede_reason: reason)
            )
          end
        end

        Models::Fact.find(keep_fact_id)
      end

      # Builds a timeline fact from point-in-time facts for an entity
      #
      # Creates a synthesized fact summarizing the entity's history on a topic.
      #
      # @param entity_id [Integer] the entity ID
      # @param topic [String, nil] optional topic filter
      # @return [FactDb::Models::Fact, nil] synthesized timeline fact or nil if no facts found
      def build_timeline_fact(entity_id:, topic: nil)
        facts = Models::Fact.mentioning_entity(entity_id)
        facts = facts.search_text(topic) if topic
        facts = facts.order(valid_at: :asc).to_a

        return nil if facts.empty?

        # Find start and end dates
        start_date = facts.first.valid_at
        end_date = facts.select { |f| f.invalid_at }.map(&:invalid_at).max

        entity = Models::Entity.find(entity_id)
        synthesized_text = "#{entity.name}: #{topic || 'timeline'} from #{start_date.to_date}"
        synthesized_text += " to #{end_date.to_date}" if end_date

        synthesize(
          facts.map(&:id),
          synthesized_text,
          valid_at: start_date,
          invalid_at: end_date
        )
      end

      private

      def calculate_synthesized_confidence(source_facts)
        confidences = source_facts.map(&:confidence)
        confidences.sum / confidences.size
      end

      def aggregate_mentions(source_facts)
        mentions = {}

        source_facts.each do |fact|
          fact.entity_mentions.each do |mention|
            key = [mention.entity_id, mention.mention_role]
            existing = mentions[key]

            if existing.nil? || mention.confidence > existing[:confidence]
              mentions[key] = {
                entity: mention.entity,
                text: mention.mention_text,
                role: mention.mention_role,
                confidence: mention.confidence
              }
            end
          end
        end

        mentions.values
      end

      def text_similarity(text1, text2)
        words1 = text1.downcase.split
        words2 = text2.downcase.split

        return 0.0 if words1.empty? || words2.empty?

        intersection = words1 & words2
        union = words1 | words2

        intersection.size.to_f / union.size
      end
    end
  end
end
