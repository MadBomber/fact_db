# frozen_string_literal: true

require "test_helper"

class EntityTest < Minitest::Test
  include FactDb::TestHelpers

  def test_entity_creation
    entity = create_entity(name: "Paula Chen", type: "person")

    assert_equal "Paula Chen", entity.name
    assert_equal "person", entity.type
    assert_equal "resolved", entity.resolution_status
  end

  def test_entity_types
    person = create_entity(type: "person")
    org = create_entity(name: "Acme Corp", type: "organization")
    place = create_entity(name: "Seattle", type: "place")

    assert_includes FactDb::Models::Entity.by_type("person"), person
    assert_includes FactDb::Models::Entity.by_type("organization"), org
    assert_includes FactDb::Models::Entity.by_type("place"), place
  end

  def test_add_alias
    entity = create_entity(name: "Paula Chen")
    entity.add_alias("P. Chen")
    entity.add_alias("@paula", type: "handle")

    assert_equal 2, entity.aliases.count
    assert_includes entity.all_aliases, "P. Chen"
    assert_includes entity.all_aliases, "@paula"
  end

  def test_matches_name
    entity = create_entity(name: "Paula Chen")
    entity.add_alias("P. Chen")

    assert entity.matches_name?("Paula Chen")
    assert entity.matches_name?("paula chen") # Case insensitive
    assert entity.matches_name?("P. Chen")
    refute entity.matches_name?("John Smith")
  end

  def test_merged_entity
    keep = create_entity(name: "Paula Chen")
    merged = create_entity(name: "P. Chen", resolution_status: "merged")
    merged.update!(canonical_id: keep.id)

    assert merged.merged?
    assert_equal keep, merged.canonical_entity
  end

  def test_not_merged_scope
    active = create_entity(name: "Paula Chen")
    merged = create_entity(name: "P. Chen", resolution_status: "merged")

    results = FactDb::Models::Entity.not_merged

    assert_includes results, active
    refute_includes results, merged
  end

  def test_entity_validation
    entity = FactDb::Models::Entity.new

    refute entity.valid?
    assert entity.errors[:name].any?
    assert entity.errors[:type].any?
  end

  def test_entity_type_validation
    entity = FactDb::Models::Entity.new(
      name: "Test",
      type: "invalid_type",
      resolution_status: "resolved"
    )

    refute entity.valid?
    assert entity.errors[:type].any?
  end
end
