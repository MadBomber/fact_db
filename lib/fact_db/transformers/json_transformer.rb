# frozen_string_literal: true

module FactDb
  module Transformers
    # JSON transformer - returns results as structured hash.
    # This is the default pass-through format.
    class JsonTransformer < Base
      # Transform results to JSON-ready hash format.
      #
      # @param results [QueryResult] The query results
      # @return [Hash] JSON-serializable hash
      def transform(results)
        results.to_h
      end
    end
  end
end
