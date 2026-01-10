# frozen_string_literal: true

module FactDb
  class Config
    module Builder
      # Build a default logger if none is configured
      #
      # @return [Logger] a logger configured with the current log level
      def build_default_logger
        logger = Logger.new($stdout)
        logger.level = log_level || :info
        logger.formatter = proc do |severity, datetime, _progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} -- FactDb: #{msg}\n"
        end
        logger
      end

      # Build an LLM client from the configured provider settings
      #
      # @return [FactDb::LLM::Adapter, nil] the LLM client or nil if not configured
      def build_default_llm_client
        provider = llm&.provider
        return nil unless provider

        LLM::Adapter.new(
          provider: provider.to_sym,
          model: llm&.model,
          api_key: llm&.api_key
        )
      end

      # Build a default embedding generator
      #
      # @return [Proc, nil] a callable that generates embeddings or nil if not configured
      def build_default_embedding_generator
        return nil unless embedding&.generator

        # If embedding.generator is already a callable, return it
        return embedding.generator if embedding.generator.respond_to?(:call)

        nil
      end

      # Reset all callables to their default values
      def reset_to_defaults
        @logger = build_default_logger
        @llm_client = build_default_llm_client
        @embedding_generator = build_default_embedding_generator
      end

      # ==========================================================================
      # Setup Defaults Callback
      # ==========================================================================

      def setup_defaults
        @logger ||= build_default_logger
        @llm_client ||= build_default_llm_client if llm&.provider
        @embedding_generator ||= build_default_embedding_generator
      end
    end
  end
end
