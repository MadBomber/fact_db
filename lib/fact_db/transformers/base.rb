# frozen_string_literal: true

module FactDb
  module Transformers
    # Base transformer class providing common utilities.
    # Subclasses implement specific output formats for LLM consumption.
    class Base
      # Transform query results to the target format.
      #
      # @param results [QueryResult] The query results
      # @return [QueryResult] Transformed results (may modify in place)
      def transform(results)
        results
      end

      protected

      # Safely get a value from hash or object
      #
      # @param obj [Hash, Object] Source object
      # @param key [Symbol] Key to retrieve
      # @return [Object, nil] The value
      def get_value(obj, key)
        if obj.is_a?(Hash)
          obj[key] || obj[key.to_s]
        elsif obj.respond_to?(key)
          obj.send(key)
        end
      end

      # Format dates consistently
      #
      # @param date [Date, Time, String, nil] Date to format
      # @return [String, nil] Formatted date string
      def format_date(date)
        return nil if date.nil?

        if date.respond_to?(:strftime)
          date.strftime("%Y-%m-%d")
        else
          date.to_s
        end
      end

      # Escape strings for output
      #
      # @param str [String] String to escape
      # @return [String] Escaped string
      def escape_string(str)
        str.to_s.gsub('"', '\\"').gsub("\n", "\\n")
      end

      # Create a variable name from a string
      #
      # @param str [String] Source string
      # @return [String] Valid variable name
      def to_variable(str)
        str.to_s
           .downcase
           .gsub(/[^a-z0-9]+/, "_")
           .gsub(/^_|_$/, "")
           .slice(0, 30)
      end

      # Truncate string to specified length
      #
      # @param str [String] String to truncate
      # @param length [Integer] Maximum length
      # @return [String] Truncated string
      def truncate(str, length)
        return str if str.to_s.length <= length

        "#{str.to_s[0, length - 3]}..."
      end
    end
  end
end
