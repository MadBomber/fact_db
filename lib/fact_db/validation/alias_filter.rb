# frozen_string_literal: true

module FactDb
  module Validation
    # Filters out invalid aliases such as pronouns, common terms, and generic references.
    # Used by extractors, services, and models to ensure alias quality.
    class AliasFilter
      # English pronouns (subject, object, possessive, reflexive)
      PRONOUNS = %w[
        i me my mine myself
        you your yours yourself yourselves
        he him his himself
        she her hers herself
        it its itself
        we us our ours ourselves
        they them their theirs themselves
        who whom whose
        this that these those
        what which
        one ones
        all any both each either neither none some
        another other others
      ].freeze

      # Common generic terms that shouldn't be aliases
      GENERIC_TERMS = %w[
        a an the
        man woman person people men women
        boy girl child children
        husband wife brother sister father mother son daughter
        king queen prince princess lord lady
        sir madam mr mrs ms miss dr
        someone something somewhere anyone anything anywhere
        everyone everything everywhere nobody nothing nowhere
        here there
        today yesterday tomorrow
        now then
      ].freeze

      # Common role/title references that are too generic
      GENERIC_ROLES = %w[
        the\ man the\ woman the\ person the\ people
        a\ man a\ woman a\ person
        this\ man this\ woman this\ person
        that\ man that\ woman that\ person
        the\ king the\ queen the\ lord the\ lady
        the\ brother the\ sister the\ father the\ mother
        the\ husband the\ wife
        the\ boy the\ girl the\ child
        believers disciples apostles
        men greek\ men
      ].freeze

      # Common first names that are too ambiguous to use as standalone aliases
      # These should only be valid when part of a fuller name
      AMBIGUOUS_FIRST_NAMES = %w[
        simon peter john james paul mark matthew luke andrew philip
        thomas james joseph mary martha elizabeth sarah anna david
        michael robert william richard henry george charles edward
        mary ann jane elizabeth margaret catherine alice
      ].freeze

      class << self
        # Check if a potential alias is valid
        # @param text [String] The alias text to validate
        # @param canonical_name [String, nil] The entity's canonical name (for comparison)
        # @return [Boolean] true if the alias is valid
        def valid?(text, canonical_name: nil)
          return false if text.nil?

          normalized = text.to_s.strip.downcase

          return false if normalized.empty?
          return false if too_short?(normalized)
          return false if pronoun?(normalized)
          return false if generic_term?(normalized)
          return false if generic_role?(normalized)
          return false if matches_canonical?(normalized, canonical_name)
          return false if only_articles_and_generic?(normalized)
          return false if ambiguous_standalone_name?(normalized, canonical_name)

          true
        end

        # Filter an array of aliases, returning only valid ones
        # @param aliases [Array<String>] Array of potential aliases
        # @param canonical_name [String, nil] The entity's canonical name
        # @return [Array<String>] Array of valid aliases
        def filter(aliases, canonical_name: nil)
          return [] unless aliases.is_a?(Array)

          aliases
            .map { |a| a.to_s.strip }
            .reject { |a| a.empty? }
            .select { |a| valid?(a, canonical_name: canonical_name) }
            .uniq { |a| a.downcase }
        end

        # Get a human-readable reason why an alias was rejected
        # @param text [String] The alias text
        # @param canonical_name [String, nil] The entity's canonical name
        # @return [String, nil] Rejection reason or nil if valid
        def rejection_reason(text, canonical_name: nil)
          return "empty or nil" if text.nil? || text.to_s.strip.empty?

          normalized = text.to_s.strip.downcase

          return "too short (less than 2 characters)" if too_short?(normalized)
          return "is a pronoun" if pronoun?(normalized)
          return "is a generic term" if generic_term?(normalized)
          return "is a generic role reference" if generic_role?(normalized)
          return "contains only articles and generic words" if only_articles_and_generic?(normalized)
          return "is an ambiguous standalone first name" if ambiguous_standalone_name?(normalized, canonical_name)

          nil
        end

        private

        def too_short?(text)
          # Single characters are almost never valid aliases
          # Exception: single uppercase letters could be initials
          text.length < 2
        end

        def pronoun?(text)
          PRONOUNS.include?(text)
        end

        def generic_term?(text)
          GENERIC_TERMS.include?(text)
        end

        def generic_role?(text)
          GENERIC_ROLES.include?(text)
        end

        def matches_canonical?(text, canonical_name)
          return false if canonical_name.nil?

          text == canonical_name.to_s.strip.downcase
        end

        def only_articles_and_generic?(text)
          words = text.split(/\s+/)
          return false if words.empty?

          # Check if all words are articles or generic terms
          filler_words = %w[a an the this that these those of and or]
          non_filler = words.reject { |w| filler_words.include?(w) || GENERIC_TERMS.include?(w) }

          non_filler.empty? || non_filler.all? { |w| PRONOUNS.include?(w) }
        end

        # Check if text is a standalone ambiguous first name
        # Single common first names are too likely to cause entity confusion
        # But "Simon Peter" or "John Mark" would be acceptable
        def ambiguous_standalone_name?(text, canonical_name)
          return false if text.nil?

          words = text.split(/\s+/)

          # Only reject if it's a single word that's a common first name
          return false unless words.length == 1

          # Check if it's in our list of ambiguous first names
          return false unless AMBIGUOUS_FIRST_NAMES.include?(text)

          # Allow if the canonical name is essentially the same
          # (e.g., "Peter" as alias for "Peter" entity)
          return false if canonical_name && canonical_name.to_s.strip.downcase == text

          # Allow if the first name matches the first word of canonical name
          # (e.g., "Simon" for "Simon Peter" is ok, but "Simon" for "Jesus" is not)
          if canonical_name
            canonical_first = canonical_name.to_s.strip.downcase.split(/\s+/).first
            return false if canonical_first == text
          end

          true
        end
      end
    end
  end
end
