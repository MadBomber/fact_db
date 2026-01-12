# frozen_string_literal: true

require "test_helper"

class EntityServiceTest < Minitest::Test
  include FactDb::TestHelpers

  def setup
    super
    @config = FactDb.config
    @service = FactDb::Services::EntityService.new(@config)
  end

  def test_relationship_types_returns_distinct_roles
    entity1 = create_entity(name: "Paula Chen", kind: "person")
    entity2 = create_entity(name: "Microsoft", kind: "organization")

    fact = create_fact(text: "Paula Chen works at Microsoft")

    FactDb::Models::EntityMention.create!(
      fact: fact,
      entity: entity1,
      mention_role: "subject",
      mention_text: "Paula Chen"
    )
    FactDb::Models::EntityMention.create!(
      fact: fact,
      entity: entity2,
      mention_role: "object",
      mention_text: "Microsoft"
    )

    roles = @service.relationship_types

    assert_includes roles, :subject
    assert_includes roles, :object
  end

  def test_relationship_types_returns_empty_when_no_mentions
    roles = @service.relationship_types

    assert_equal [], roles
  end

  def test_relationship_types_for_entity
    entity = create_entity(name: "Paula Chen", kind: "person")
    org = create_entity(name: "Microsoft", kind: "organization")

    fact1 = create_fact(text: "Paula Chen works at Microsoft")
    fact2 = create_fact(text: "Paula Chen reports to John")

    FactDb::Models::EntityMention.create!(
      fact: fact1,
      entity: entity,
      mention_role: "subject",
      mention_text: "Paula Chen"
    )
    FactDb::Models::EntityMention.create!(
      fact: fact2,
      entity: entity,
      mention_role: "subject",
      mention_text: "Paula Chen"
    )
    FactDb::Models::EntityMention.create!(
      fact: fact1,
      entity: org,
      mention_role: "object",
      mention_text: "Microsoft"
    )

    roles = @service.relationship_types_for(entity.id)

    assert_includes roles, :subject
    refute_includes roles, :object
  end

  def test_relationship_types_for_entity_returns_empty_when_none
    entity = create_entity(name: "Paula Chen", kind: "person")

    roles = @service.relationship_types_for(entity.id)

    assert_equal [], roles
  end

  def test_timespan_for_entity
    Timecop.freeze(Time.local(2024, 6, 15, 12, 0, 0)) do
      entity = create_entity(name: "Paula Chen", kind: "person")

      fact1 = create_fact(text: "Paula Chen joined", valid_at: Date.new(2024, 1, 10))
      fact2 = create_fact(text: "Paula Chen promoted", valid_at: Date.new(2024, 3, 15))

      FactDb::Models::EntityMention.create!(
        fact: fact1,
        entity: entity,
        mention_role: "subject",
        mention_text: "Paula Chen"
      )
      FactDb::Models::EntityMention.create!(
        fact: fact2,
        entity: entity,
        mention_role: "subject",
        mention_text: "Paula Chen"
      )

      timespan = @service.timespan_for(entity.id)

      assert_equal Date.new(2024, 1, 10), timespan[:from]
      assert_equal Date.new(2024, 3, 15), timespan[:to]
    end
  end

  def test_timespan_for_entity_with_no_facts
    Timecop.freeze(Time.local(2024, 6, 15, 12, 0, 0)) do
      entity = create_entity(name: "Paula Chen", kind: "person")

      timespan = @service.timespan_for(entity.id)

      assert_nil timespan[:from]
      assert_equal Date.today, timespan[:to]
    end
  end
end
