# frozen_string_literal: true

module FactDb
  module Extractors
    class RuleBasedExtractor < Base
      # Date patterns for temporal extraction
      DATE_PATTERNS = [
        # "on January 10, 2024"
        /(?:on|since|from|as of|starting)\s+(\w+\s+\d{1,2},?\s+\d{4})/i,
        # "on 2024-01-10"
        /(?:on|since|from|as of|starting)\s+(\d{4}-\d{2}-\d{2})/i,
        # "in January 2024"
        /(?:in|during)\s+(\w+\s+\d{4})/i,
        # "in 2024"
        /(?:in|during)\s+(\d{4})\b/i
      ].freeze

      END_DATE_PATTERNS = [
        # "until January 10, 2024"
        /(?:until|through|to|ended|left)\s+(\w+\s+\d{1,2},?\s+\d{4})/i,
        /(?:until|through|to|ended|left)\s+(\d{4}-\d{2}-\d{2})/i
      ].freeze

      # Employment patterns (use [ ]+ instead of \s+ to avoid matching newlines)
      EMPLOYMENT_PATTERNS = [
        # "Paula works at Microsoft"
        /(\b[A-Z][a-z]+(?:[ ]+[A-Z][a-z]+)*)\b[ ]+(?:works?|worked|is working)[ ]+(?:at|for)[ ]+(\b[A-Z][A-Za-z]+(?:[ ]+[A-Z][A-Za-z]+)*)\b/,
        # "Paula joined Microsoft"
        /(\b[A-Z][a-z]+(?:[ ]+[A-Z][a-z]+)*)\b[ ]+(?:joined|started at|was hired by)[ ]+(\b[A-Z][A-Za-z]+(?:[ ]+[A-Z][A-Za-z]+)*)\b/,
        # "Paula left Microsoft"
        /(\b[A-Z][a-z]+(?:[ ]+[A-Z][a-z]+)*)\b[ ]+(?:left|departed|resigned from|was fired from)[ ]+(\b[A-Z][A-Za-z]+(?:[ ]+[A-Z][A-Za-z]+)*)\b/,
        # "Paula is a Principal Engineer at Microsoft"
        /(\b[A-Z][a-z]+(?:[ ]+[A-Z][a-z]+)*)\b[ ]+(?:is|was|became)[ ]+(?:a[ ]+)?([A-Z][A-Za-z]+(?:[ ]+[A-Z][A-Za-z]+)*)[ ]+at[ ]+(\b[A-Z][A-Za-z]+(?:[ ]+[A-Z][A-Za-z]+)*)\b/
      ].freeze

      # Relationship patterns (use [ ]+ instead of \s+ to avoid matching newlines)
      RELATIONSHIP_PATTERNS = [
        # "Paula is married to John"
        /(\b[A-Z][a-z]+(?:[ ]+[A-Z][a-z]+)*)\b[ ]+(?:is|was)[ ]+(?:married to|engaged to|dating)[ ]+(\b[A-Z][a-z]+(?:[ ]+[A-Z][a-z]+)*)\b/,
        # "Paula is the CEO of Microsoft"
        /(\b[A-Z][a-z]+(?:[ ]+[A-Z][a-z]+)*)\b[ ]+(?:is|was)[ ]+(?:the[ ]+)?(\w+(?:[ ]+\w+)*)[ ]+of[ ]+(\b[A-Z][A-Za-z]+(?:[ ]+[A-Z][A-Za-z]+)*)\b/
      ].freeze

      # Location patterns (use [ ]+ instead of \s+ to avoid matching newlines)
      # Location capture includes multi-word cities like "New York City", "San Francisco"
      LOCATION_PATTERNS = [
        # "Paula lives in Seattle" or "Bob lives in New York City"
        /(\b[A-Z][a-z]+(?:[ ]+[A-Z][a-z]+)*)\b[ ]+(?:lives?|lived|is based|was based|relocated|moved)[ ]+(?:in|to)[ ]+(\b[A-Z][A-Za-z]+(?:[ ]+[A-Z][A-Za-z]+)*(?:,[ ]+[A-Z]{2})?)\b/,
        # "Microsoft is headquartered in Redmond" or "in Seattle, Washington"
        /(\b[A-Z][A-Za-z]+(?:[ ]+[A-Z][A-Za-z]+)*)\b[ ]+(?:is|was)[ ]+(?:headquartered|located|based)[ ]+in[ ]+(\b[A-Z][A-Za-z]+(?:[ ]+[A-Z][A-Za-z]+)*(?:,[ ]+[A-Z][A-Za-z]+)?)\b/
      ].freeze

      def extract(text, context = {})
        return [] if text.nil? || text.strip.empty?

        facts = []

        # Extract employment facts
        facts.concat(extract_employment_facts(text, context))

        # Extract relationship facts
        facts.concat(extract_relationship_facts(text, context))

        # Extract location facts
        facts.concat(extract_location_facts(text, context))

        facts.uniq { |f| f[:text] }
      end

      def extract_entities(text)
        return [] if text.nil? || text.strip.empty?

        entities = []

        # Extract person names (capitalized word sequences on same line)
        # Use [ ]+ instead of \s+ to avoid matching across newlines
        text.scan(/\b([A-Z][a-z]+(?:[ ]+[A-Z][a-z]+)+)\b/).flatten.uniq.each do |name|
          next if common_word?(name)
          next if job_title?(name)
          next if common_phrase?(name)
          next if known_place?(name)
          next if organization_indicator?(name)

          entities << build_entity(name: name, type: "person")
        end

        # Extract organization names (from employment patterns)
        EMPLOYMENT_PATTERNS.each do |pattern|
          text.scan(pattern).each do |match|
            org_name = match.last
            entities << build_entity(name: org_name, type: "organization") unless common_word?(org_name)
          end
        end

        # Extract locations
        LOCATION_PATTERNS.each do |pattern|
          text.scan(pattern).each do |match|
            location = match.last
            entities << build_entity(name: location, type: "place") unless common_word?(location)
          end
        end

        entities.uniq { |e| e[:name].downcase }
      end

      private

      def extract_employment_facts(text, context)
        facts = []
        default_date = context[:captured_at] || Time.current

        EMPLOYMENT_PATTERNS.each do |pattern|
          text.scan(pattern).each do |match|
            person, *rest = match
            org = rest.last

            # Determine if this is a "left" pattern
            is_termination = text.match?(/#{Regexp.escape(person)}\s+(?:left|departed|resigned|was fired)/i)

            fact_text = match.join(" ").gsub(/\s+/, " ")
            valid_at = extract_start_date(text) || default_date
            invalid_at = is_termination ? (extract_end_date(text) || default_date) : nil

            mentions = [
              build_mention(name: person, type: "person", role: "subject"),
              build_mention(name: org, type: "organization", role: "object")
            ]

            # Add role if present
            if rest.length > 1
              mentions << build_mention(name: rest[0], type: "concept", role: "instrument")
            end

            facts << build_fact(
              text: fact_text,
              valid_at: valid_at,
              invalid_at: invalid_at,
              mentions: mentions,
              confidence: 0.8
            )
          end
        end

        facts
      end

      def extract_relationship_facts(text, context)
        facts = []
        default_date = context[:captured_at] || Time.current

        RELATIONSHIP_PATTERNS.each do |pattern|
          text.scan(pattern).each do |match|
            fact_text = match.join(" ").gsub(/\s+/, " ")

            mentions = match.map.with_index do |name, i|
              role = i.zero? ? "subject" : "object"
              build_mention(name: name, type: "person", role: role)
            end

            facts << build_fact(
              text: fact_text,
              valid_at: extract_start_date(text) || default_date,
              invalid_at: extract_end_date(text),
              mentions: mentions,
              confidence: 0.75
            )
          end
        end

        facts
      end

      def extract_location_facts(text, context)
        facts = []
        default_date = context[:captured_at] || Time.current

        LOCATION_PATTERNS.each do |pattern|
          text.scan(pattern).each do |match|
            entity_name, location = match
            fact_text = "#{entity_name} is located in #{location}"

            # Determine entity type
            entity_type = text.match?(/#{Regexp.escape(entity_name)}\s+(?:lives?|lived)/i) ? "person" : "organization"

            mentions = [
              build_mention(name: entity_name, type: entity_type, role: "subject"),
              build_mention(name: location, type: "place", role: "location")
            ]

            facts << build_fact(
              text: fact_text,
              valid_at: extract_start_date(text) || default_date,
              invalid_at: nil,
              mentions: mentions,
              confidence: 0.7
            )
          end
        end

        facts
      end

      def extract_start_date(text)
        DATE_PATTERNS.each do |pattern|
          if (match = text.match(pattern))
            return parse_date(match[1])
          end
        end
        nil
      end

      def extract_end_date(text)
        END_DATE_PATTERNS.each do |pattern|
          if (match = text.match(pattern))
            return parse_date(match[1])
          end
        end
        nil
      end

      def common_word?(word)
        common_words = %w[
          The A An And Or But Is Was Were Are Been
          Has Have Had Will Would Could Should
          This That These Those
          January February March April May June July August September October November December
          Monday Tuesday Wednesday Thursday Friday Saturday Sunday
          Inc Corp Ltd LLC Company Corporation
        ]
        common_words.any? { |w| w.casecmp?(word) }
      end

      def job_title?(text)
        # Common job title words that indicate this is a role, not a person name
        title_indicators = %w[
          Chief Executive Officer Director Manager Engineer Developer
          President Vice Principal Senior Junior Lead Head
          Analyst Coordinator Administrator Assistant Specialist
          Consultant Architect Designer Technician Supervisor
          CTO CEO CFO COO CMO CIO CPO
          VP SVP EVP
        ]

        words = text.split(/\s+/)

        # If any word is a title indicator, it's likely a job title
        words.any? { |word| title_indicators.any? { |t| t.casecmp?(word) } }
      end

      def common_phrase?(text)
        # Common document phrases that are not person names
        phrases = [
          /Team\s+Updates?/i,
          /Action\s+Items?/i,
          /Meeting\s+Notes?/i,
          /Status\s+Meeting/i,
          /Project\s+Status/i,
          /Human\s+Resources?/i,
          /Best\s+Regards?/i,
          /Immediate\s+Release/i,
          /New\s+Leadership/i,
          /Appoints?\s+New/i,
          /Recent\s+\w+/i,
          /Please\s+\w+/i
        ]

        phrases.any? { |pattern| text.match?(pattern) }
      end

      def known_place?(text)
        # Common city/place names or location indicators
        place_indicators = %w[
          City County State Province District Region
          Beach Park Heights Hills Valley Springs Lake
          Island Harbor Port
        ]

        # Common multi-word US city names
        known_cities = [
          "New York", "Los Angeles", "San Francisco", "San Diego", "San Jose",
          "San Antonio", "Las Vegas", "Salt Lake", "New Orleans", "Fort Worth",
          "Fort Lauderdale", "St Louis", "St Paul", "El Paso", "Santa Fe",
          "Santa Monica", "Palm Beach", "Long Beach", "Virginia Beach"
        ]

        words = text.split(/\s+/)

        # Check for place indicator words
        return true if words.any? { |word| place_indicators.any? { |p| p.casecmp?(word) } }

        # Check for known city names
        known_cities.any? { |city| text.casecmp?(city) || text.start_with?("#{city} ") }
      end

      def organization_indicator?(text)
        # Words that indicate an organization, not a person
        org_indicators = %w[
          Solutions Technologies Systems Services Group
          Partners Associates Consulting Agency
          Industries Enterprises Holdings Ventures
          Foundation Institute University College
          Global International National Regional
          Tech Corp Labs
        ]

        words = text.split(/\s+/)

        # If any word is an org indicator, it's likely an organization
        words.any? { |word| org_indicators.any? { |o| o.casecmp?(word) } }
      end
    end
  end
end
