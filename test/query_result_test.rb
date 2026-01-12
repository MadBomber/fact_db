# frozen_string_literal: true

require "test_helper"

class QueryResultTest < Minitest::Test
  include FactDb::TestHelpers

  def test_initialization
    result = FactDb::QueryResult.new(query: "Paula Chen")

    assert_equal "Paula Chen", result.query
    assert_empty result.facts
    assert_empty result.entities
    assert_instance_of Hash, result.metadata
    assert result.metadata[:retrieved_at]
    assert_equal [:fact_db], result.metadata[:stores_queried]
  end

  def test_add_facts_with_hashes
    result = FactDb::QueryResult.new(query: "test")

    result.add_facts([
      { id: 1, fact_text: "Fact one", status: "canonical" },
      { id: 2, fact_text: "Fact two", status: "canonical" }
    ])

    assert_equal 2, result.fact_count
    assert_equal "Fact one", result.facts.first[:fact_text]
  end

  def test_add_facts_with_nil_or_empty
    result = FactDb::QueryResult.new(query: "test")

    result.add_facts(nil)
    assert_empty result.facts

    result.add_facts([])
    assert_empty result.facts
  end

  def test_add_facts_with_objects
    result = FactDb::QueryResult.new(query: "test")
    fact = create_fact(text: "Paula works at Microsoft")

    result.add_facts([fact])

    assert_equal 1, result.fact_count
    assert_equal "Paula works at Microsoft", result.facts.first[:fact_text]
  end

  def test_empty_check
    result = FactDb::QueryResult.new(query: "test")

    assert result.empty?

    result.add_facts([{ id: 1, fact_text: "Test" }])

    refute result.empty?
  end

  def test_to_h
    Timecop.freeze(Time.local(2024, 6, 15, 12, 0, 0)) do
      result = FactDb::QueryResult.new(query: "Paula Chen")
      result.add_facts([{ id: 1, fact_text: "Test fact" }])

      hash = result.to_h

      assert_equal "Paula Chen", hash[:query]
      assert_equal 1, hash[:facts].size
      assert_instance_of Hash, hash[:entities]
      assert_instance_of Hash, hash[:metadata]
    end
  end

  def test_each_fact
    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([
      { id: 1, fact_text: "Fact one" },
      { id: 2, fact_text: "Fact two" }
    ])

    texts = []
    result.each_fact { |f| texts << f[:fact_text] }

    assert_equal ["Fact one", "Fact two"], texts
  end

  def test_each_entity
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => { id: 1, name: "Paula Chen" },
      2 => { id: 2, name: "Microsoft" }
    })

    names = []
    result.each_entity { |e| names << e[:name] }

    assert_equal ["Paula Chen", "Microsoft"], names
  end

  def test_fact_count_and_entity_count
    result = FactDb::QueryResult.new(query: "test")

    assert_equal 0, result.fact_count
    assert_equal 0, result.entity_count

    result.add_facts([{ id: 1, fact_text: "Test" }])
    result.instance_variable_set(:@entities, { 1 => { id: 1, name: "Test Entity" } })

    assert_equal 1, result.fact_count
    assert_equal 1, result.entity_count
  end

  def test_items_returns_normalized_format
    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([
      { id: 1, fact_text: "Fact one", valid_at: Date.new(2024, 1, 15) }
    ])

    items = result.items

    assert_equal 1, items.size
    assert_equal :fact, items.first[:type]
    assert_equal "Fact one", items.first[:text]
    assert_equal Date.new(2024, 1, 15), items.first[:valid_at]
  end

  def test_resolve_entities_with_nil_service
    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([{ id: 1, fact_text: "Test", entity_mentions: [{ entity_id: 1, mention_role: "subject" }] }])

    result.resolve_entities(nil)

    assert_empty result.entities
  end

  def test_resolve_entities_caches_entities
    result = FactDb::QueryResult.new(query: "test")
    entity = create_entity(name: "Paula Chen", type: "person")
    result.add_facts([
      { id: 1, fact_text: "Test", entity_mentions: [{ entity_id: entity.id, mention_role: "subject" }] }
    ])

    # Use a simple stub object instead of Minitest::Mock
    stub_service = Object.new
    stub_service.define_singleton_method(:find) { |id| entity if id == entity.id }

    result.resolve_entities(stub_service)

    assert_equal 1, result.entity_count
    assert_equal "Paula Chen", result.entities[entity.id][:name]
  end
end
