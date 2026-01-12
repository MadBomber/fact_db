# frozen_string_literal: true

module FactDb
  module Transformers
    # Transforms results into Cypher-like graph notation.
    # This format is readable by both humans and LLMs, and encodes
    # nodes, relationships, and properties explicitly.
    #
    # @example Output format
    #   (paula:Person {name: "Paula Chen"})
    #   (microsoft:Organization {name: "Microsoft"})
    #   (paula)-[:WORKS_AT {since: "2024-01-10", role: "Principal Engineer"}]->(microsoft)
    class CypherTransformer < Base
      # Transform results to Cypher format.
      #
      # @param results [QueryResult] The query results
      # @return [String] Cypher-like graph notation
      def transform(results)
        lines = []
        defined_nodes = Set.new

        # Define entity nodes
        results.each_entity do |entity|
          node_def = entity_to_cypher(entity)
          if node_def && !defined_nodes.include?(node_def)
            lines << node_def
            defined_nodes << node_def
          end
        end

        # Define relationships from facts
        results.each_fact do |fact|
          relationship = fact_to_cypher(fact, results.entities, defined_nodes, lines)
          lines << relationship if relationship
        end

        lines.join("\n")
      end

      private

      def entity_to_cypher(entity)
        name = get_value(entity, :canonical_name) || get_value(entity, :name)
        return nil unless name

        var = to_variable(name)
        entity_type = get_value(entity, :type) || "Entity"
        label = entity_type.to_s.capitalize

        props = { name: name }

        # Add aliases if present
        aliases = get_value(entity, :aliases)
        if aliases && !aliases.empty?
          alias_texts = aliases.map { |a| a.is_a?(Hash) ? a[:alias_text] : a.to_s }
          props[:aliases] = alias_texts
        end

        "(#{var}:#{label} #{format_props(props)})"
      end

      def fact_to_cypher(fact, entities, defined_nodes, lines)
        fact_text = get_value(fact, :fact_text) || ""
        return nil if fact_text.empty?

        mentions = get_value(fact, :entity_mentions) || []

        # Find subject and object from mentions if available
        subject_mention = mentions.find { |m| get_value(m, :mention_role) == "subject" }
        object_mention = mentions.find { |m| get_value(m, :mention_role) != "subject" }

        # Get subject - from mentions or parse from fact_text
        if subject_mention
          subject_id = get_value(subject_mention, :entity_id)
          subject_entity = entities[subject_id]
          subject_name = subject_entity ? (get_value(subject_entity, :canonical_name) || get_value(subject_entity, :name)) : "Entity_#{subject_id}"
        else
          subject_name = extract_subject(fact_text)
        end

        return nil if subject_name.nil? || subject_name.empty?

        subject_var = to_variable(subject_name)

        # Ensure subject node is defined
        unless defined_nodes.any? { |n| n.include?("(#{subject_var}:") }
          node_def = "(#{subject_var}:Entity {name: \"#{escape_string(subject_name)}\"})"
          lines << node_def
          defined_nodes << node_def
        end

        # Build relationship properties
        rel_props = {}

        valid_at = get_value(fact, :valid_at)
        rel_props[:since] = format_date(valid_at) if valid_at

        invalid_at = get_value(fact, :invalid_at)
        rel_props[:until] = format_date(invalid_at) if invalid_at

        status = get_value(fact, :status)
        rel_props[:status] = status if status

        confidence = get_value(fact, :confidence)
        rel_props[:confidence] = confidence if confidence

        # Extract relationship type from fact text
        rel_type = extract_relationship_type(fact_text)

        if object_mention
          # Relationship to another entity
          object_id = get_value(object_mention, :entity_id)
          object_entity = entities[object_id]
          object_name = object_entity ? (get_value(object_entity, :canonical_name) || get_value(object_entity, :name)) : "Entity_#{object_id}"
          object_var = to_variable(object_name)

          # Ensure object node is defined
          unless defined_nodes.any? { |n| n.include?("(#{object_var}:") }
            node_def = "(#{object_var}:Entity {name: \"#{escape_string(object_name)}\"})"
            lines << node_def
            defined_nodes << node_def
          end

          props_str = rel_props.empty? ? "" : " #{format_props(rel_props)}"
          "(#{subject_var})-[:#{rel_type}#{props_str}]->(#{object_var})"
        else
          # Relationship to a literal value
          object_value = extract_object_value(fact_text, subject_name)
          props_str = rel_props.empty? ? "" : " #{format_props(rel_props)}"
          "(#{subject_var})-[:#{rel_type}#{props_str}]->(\"#{escape_string(object_value)}\")"
        end
      end

      def extract_relationship_type(fact_text)
        if fact_text.match?(/\bworks?\s+(at|for)\b/i)
          "WORKS_AT"
        elsif fact_text.match?(/\bworked\s+(at|for)\b/i)
          "WORKED_AT"
        elsif fact_text.match?(/\breports?\s+to\b/i)
          "REPORTS_TO"
        elsif fact_text.match?(/\bis\s+(a|an|the)\b/i)
          "IS_A"
        elsif fact_text.match?(/\bis\s+\w+/i)
          "IS"
        elsif fact_text.match?(/\bhas\b/i)
          "HAS"
        elsif fact_text.match?(/\bdecided\b/i)
          "DECIDED"
        elsif fact_text.match?(/\bjoined\b/i)
          "JOINED"
        elsif fact_text.match?(/\bleft\b/i)
          "LEFT"
        else
          "RELATES_TO"
        end
      end

      def extract_subject(fact_text)
        words = fact_text.split(/\s+/)
        words.take_while { |w| !w.match?(/^(is|are|was|were|has|have|works|worked|reports)$/i) }.join(" ")
      end

      def extract_object_value(fact_text, subject)
        remainder = fact_text.sub(/^#{Regexp.escape(subject)}\s*/i, "")
        remainder.sub(/^(is|are|was|were|has|have|works?|worked|reports?)\s+(at|for|to|a|an|the)?\s*/i, "")
      end

      def format_props(props)
        return "{}" if props.empty?

        pairs = props.map do |k, v|
          value = case v
                  when String then "\"#{escape_string(v)}\""
                  when Array then "[#{v.map { |e| "\"#{escape_string(e)}\"" }.join(", ")}]"
                  when nil then "null"
                  else v.to_s
                  end
          "#{k}: #{value}"
        end

        "{#{pairs.join(", ")}}"
      end
    end
  end
end
