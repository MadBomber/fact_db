# frozen_string_literal: true

require "simple_flow"

module FactDb
  module Pipeline
    # Pipeline for extracting facts from sources using SimpleFlow
    # Supports parallel processing of multiple source items
    #
    # @example Sequential extraction
    #   pipeline = ExtractionPipeline.new(config)
    #   results = pipeline.process([source1, source2], extractor: :llm)
    #
    # @example Parallel extraction
    #   pipeline = ExtractionPipeline.new(config)
    #   results = pipeline.process_parallel([source1, source2, source3], extractor: :llm)
    #
    class ExtractionPipeline
      attr_reader :config

      def initialize(config = FactDb.config)
        @config = config
      end

      # Process multiple source items sequentially
      #
      # @param sources [Array<Models::Source>] Source records to process
      # @param extractor [Symbol] Extractor type (:manual, :llm, :rule_based)
      # @return [Array<Hash>] Results with extracted facts per source
      def process(sources, extractor: config.default_extractor)
        pipeline = build_extraction_pipeline(extractor)

        sources.map do |source|
          result = pipeline.call(SimpleFlow::Result.new(source))
          {
            source_id: source.id,
            facts: result.success? ? result.value : [],
            error: result.halted? ? result.error : nil
          }
        end
      end

      # Process multiple source items in parallel
      # Uses SimpleFlow's parallel execution capabilities
      #
      # @param sources [Array<Models::Source>] Source records to process
      # @param extractor [Symbol] Extractor type (:manual, :llm, :rule_based)
      # @return [Array<Hash>] Results with extracted facts per source
      def process_parallel(sources, extractor: config.default_extractor)
        pipeline = build_parallel_pipeline(sources, extractor)
        initial_result = SimpleFlow::Result.new(sources: sources, results: {})

        final_result = pipeline.call(initial_result)

        sources.map do |source|
          result = final_result.value[:results][source.id]
          {
            source_id: source.id,
            facts: result&.dig(:facts) || [],
            error: result&.dig(:error)
          }
        end
      end

      private

      def build_extraction_pipeline(extractor)
        extractor_instance = get_extractor(extractor)

        SimpleFlow::Pipeline.new do
          # Step 1: Validate source
          step ->(result) {
            source = result.value
            if source.nil? || source.content.blank?
              result.halt("Source content is empty or missing")
            else
              result.continue(source)
            end
          }

          # Step 2: Extract facts
          step ->(result) {
            source = result.value
            begin
              facts = extractor_instance.extract(source)
              result.continue(facts)
            rescue StandardError => e
              result.halt("Extraction failed: #{e.message}")
            end
          }

          # Step 3: Validate extracted facts
          step ->(result) {
            facts = result.value
            valid_facts = facts.select { |f| f.valid? }
            result.continue(valid_facts)
          }
        end
      end

      def build_parallel_pipeline(sources, extractor)
        extractor_instance = get_extractor(extractor)

        SimpleFlow::Pipeline.new do
          # Create a step for each source item
          sources.each do |source|
            step "extract_#{source.id}", depends_on: [] do |result|
              begin
                facts = extractor_instance.extract(source)
                valid_facts = facts.select { |f| f.valid? }

                new_results = result.value[:results].merge(
                  source.id => { facts: valid_facts, error: nil }
                )
                result.continue(result.value.merge(results: new_results))
              rescue StandardError => e
                new_results = result.value[:results].merge(
                  source.id => { facts: [], error: e.message }
                )
                result.continue(result.value.merge(results: new_results))
              end
            end
          end

          # Aggregate results
          step "aggregate", depends_on: sources.map { |s| "extract_#{s.id}" } do |result|
            result.continue(result.value)
          end
        end
      end

      def get_extractor(extractor)
        case extractor.to_sym
        when :manual
          Extractors::ManualExtractor.new(config)
        when :llm
          Extractors::LLMExtractor.new(config)
        when :rule_based
          Extractors::RuleBasedExtractor.new(config)
        else
          raise ConfigurationError, "Unknown extractor: #{extractor}"
        end
      end
    end
  end
end
