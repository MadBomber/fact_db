# frozen_string_literal: true

module FactDb
  module Models
    # Join model linking entities to facts with role information
    #
    # Represents how an entity is mentioned in a specific fact, including
    # the exact text used and the semantic role (subject, object, etc.).
    #
    # @example Create a mention
    #   mention = EntityMention.create!(
    #     fact: fact, entity: person,
    #     mention_text: "John", mention_role: "subject"
    #   )
    #
    class EntityMention < ActiveRecord::Base
      self.table_name = "fact_db_entity_mentions"

      belongs_to :fact, class_name: "FactDb::Models::Fact"
      belongs_to :entity, class_name: "FactDb::Models::Entity"

      validates :mention_text, presence: true
      validates :fact_id, uniqueness: { scope: [:entity_id, :mention_text] }

      # @return [Array<String>] valid mention roles
      ROLES = %w[subject object location temporal instrument beneficiary].freeze

      validates :mention_role, inclusion: { in: ROLES }, allow_nil: true

      # @!method by_role(role)
      #   Returns mentions with a specific role
      #   @param role [String] the mention role
      #   @return [ActiveRecord::Relation]
      scope :by_role, ->(role) { where(mention_role: role) }

      # @!method subjects
      #   Returns mentions with subject role
      #   @return [ActiveRecord::Relation]
      scope :subjects, -> { by_role("subject") }

      # @!method objects
      #   Returns mentions with object role
      #   @return [ActiveRecord::Relation]
      scope :objects, -> { by_role("object") }

      # @!method high_confidence
      #   Returns mentions with confidence >= 0.9
      #   @return [ActiveRecord::Relation]
      scope :high_confidence, -> { where("confidence >= ?", 0.9) }

      # Checks if this mention has the subject role
      #
      # @return [Boolean] true if mention_role is "subject"
      def subject?
        mention_role == "subject"
      end

      # Checks if this mention has the object role
      #
      # @return [Boolean] true if mention_role is "object"
      def object?
        mention_role == "object"
      end
    end
  end
end
