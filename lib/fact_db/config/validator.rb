# frozen_string_literal: true

module FactDb
  class Config
    module Validator
      SUPPORTED_LLM_PROVIDERS = %i[
        openai anthropic gemini ollama bedrock openrouter
      ].freeze

      SUPPORTED_EXTRACTORS = %w[manual rule_based llm].freeze

      def validate_config
        validate_llm_provider
        validate_default_extractor
        validate_ranking_weights
      end

      def validate_llm_provider
        provider = llm&.provider
        return if provider.nil?

        provider_sym = provider.is_a?(Symbol) ? provider : provider.to_sym
        return if SUPPORTED_LLM_PROVIDERS.include?(provider_sym)

        raise_validation_error(
          "llm.provider must be one of: #{SUPPORTED_LLM_PROVIDERS.join(', ')} (got #{provider.inspect})"
        )
      end

      def validate_default_extractor
        extractor = default_extractor
        return if extractor.nil?

        extractor_str = extractor.to_s
        return if SUPPORTED_EXTRACTORS.include?(extractor_str)

        raise_validation_error(
          "default_extractor must be one of: #{SUPPORTED_EXTRACTORS.join(', ')} (got #{extractor.inspect})"
        )
      end

      def validate_ranking_weights
        return unless ranking

        total = (ranking.ts_rank_weight || 0).to_f +
                (ranking.vector_similarity_weight || 0).to_f +
                (ranking.entity_mention_weight || 0).to_f +
                (ranking.direct_answer_weight || 0).to_f +
                (ranking.term_overlap_weight || 0).to_f +
                (ranking.relationship_match_weight || 0).to_f +
                (ranking.confidence_weight || 0).to_f

        return if (0.95..1.05).cover?(total)

        raise_validation_error("ranking weights should sum to approximately 1.0 (got #{total})")
      end

      def validate_callables
        if @embedding_generator && !@embedding_generator.respond_to?(:call)
          raise ValidationError, "embedding_generator must be callable"
        end

        if @llm_client && !(@llm_client.respond_to?(:chat) || @llm_client.respond_to?(:call))
          raise ValidationError, "llm_client must respond to :chat or :call"
        end
      end

      def validate_logger
        return unless @logger

        unless @logger.respond_to?(:info) && @logger.respond_to?(:warn) && @logger.respond_to?(:error)
          raise ValidationError, "logger must respond to :info, :warn, and :error"
        end
      end

      private

      def raise_validation_error(message)
        raise ConfigurationError, message
      end
    end
  end
end
