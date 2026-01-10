# frozen_string_literal: true

module FactDb
  module Transformers
    # Returns raw ActiveRecord objects without transformation.
    #
    # Use this format when you need direct access to the database objects,
    # such as when you want to:
    # - Access ActiveRecord associations (entity_mentions, fact_sources)
    # - Perform additional database queries on the results
    # - Use ActiveRecord methods like update, destroy, or reload
    # - Chain additional scopes or queries
    #
    # @example Basic usage
    #   results = facts.query_facts(topic: "Paula Chen", format: :raw)
    #   results.each do |fact|
    #     puts fact.fact_text
    #     fact.entity_mentions.each { |m| puts m.entity.canonical_name }
    #   end
    #
    # @example Chaining queries
    #   results = facts.query_facts(topic: "Microsoft", format: :raw)
    #   recent = results.select { |f| f.valid_at > 1.month.ago }
    #
    class RawTransformer < Base
      # Return raw results without transformation.
      #
      # @param results [QueryResult] The query results
      # @return [Array<FactDb::Models::Fact>] Original ActiveRecord Fact objects
      def transform(results)
        results.raw_facts
      end
    end
  end
end
