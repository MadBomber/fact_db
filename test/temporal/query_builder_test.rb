# frozen_string_literal: true

require "test_helper"

class QueryBuilderTest < Minitest::Test
  include FactDb::TestHelpers

  def test_initialization
    stub_facts = create_stub_facts
    date = Date.new(2024, 1, 15)

    builder = FactDb::Temporal::QueryBuilder.new(stub_facts, date)

    assert_equal date, builder.date
  end

  def test_query_delegates_to_facts
    date = Date.new(2024, 1, 15)
    called_with = nil

    stub_facts = Object.new
    stub_facts.define_singleton_method(:query_facts) do |**args|
      called_with = args
      []
    end

    builder = FactDb::Temporal::QueryBuilder.new(stub_facts, date)
    builder.query("Paula's role", format: :cypher)

    assert_equal "Paula's role", called_with[:topic]
    assert_equal date, called_with[:at]
    assert_equal :cypher, called_with[:format]
  end

  def test_facts_delegates_to_facts_at
    date = Date.new(2024, 1, 15)
    called_with = nil

    stub_facts = Object.new
    stub_facts.define_singleton_method(:facts_at) do |at_date, **args|
      called_with = { date: at_date, args: args }
      []
    end

    builder = FactDb::Temporal::QueryBuilder.new(stub_facts, date)
    builder.facts(format: :json)

    assert_equal date, called_with[:date]
    assert_equal :json, called_with[:args][:format]
  end

  def test_facts_for_includes_entity_id
    date = Date.new(2024, 1, 15)
    entity_id = 42
    called_with = nil

    stub_facts = Object.new
    stub_facts.define_singleton_method(:facts_at) do |at_date, **args|
      called_with = { date: at_date, args: args }
      []
    end

    builder = FactDb::Temporal::QueryBuilder.new(stub_facts, date)
    builder.facts_for(entity_id, format: :json)

    assert_equal date, called_with[:date]
    assert_equal entity_id, called_with[:args][:entity]
    assert_equal :json, called_with[:args][:format]
  end

  def test_compare_to_delegates_to_diff
    date = Date.new(2024, 1, 15)
    other_date = Date.new(2024, 6, 15)
    called_with = nil

    stub_facts = Object.new
    stub_facts.define_singleton_method(:diff) do |topic, **args|
      called_with = { topic: topic, args: args }
      {}
    end

    builder = FactDb::Temporal::QueryBuilder.new(stub_facts, date)
    builder.compare_to(other_date)

    assert_nil called_with[:topic]
    assert_equal date, called_with[:args][:from]
    assert_equal other_date, called_with[:args][:to]
  end

  def test_compare_to_with_topic
    date = Date.new(2024, 1, 15)
    other_date = Date.new(2024, 6, 15)
    topic = "Paula's role"
    called_with = nil

    stub_facts = Object.new
    stub_facts.define_singleton_method(:diff) do |t, **args|
      called_with = { topic: t, args: args }
      {}
    end

    builder = FactDb::Temporal::QueryBuilder.new(stub_facts, date)
    builder.compare_to(other_date, topic: topic)

    assert_equal topic, called_with[:topic]
    assert_equal date, called_with[:args][:from]
    assert_equal other_date, called_with[:args][:to]
  end

  def test_state_for_delegates_to_facts_at
    date = Date.new(2024, 1, 15)
    entity_id = 42
    called_with = nil

    stub_facts = Object.new
    stub_facts.define_singleton_method(:facts_at) do |at_date, **args|
      called_with = { date: at_date, args: args }
      []
    end

    builder = FactDb::Temporal::QueryBuilder.new(stub_facts, date)
    builder.state_for(entity_id, format: :json)

    assert_equal date, called_with[:date]
    assert_equal entity_id, called_with[:args][:entity]
    assert_equal :json, called_with[:args][:format]
  end

  private

  def create_stub_facts
    Object.new.tap do |stub|
      stub.define_singleton_method(:query_facts) { |**_args| [] }
      stub.define_singleton_method(:facts_at) { |_date, **_args| [] }
      stub.define_singleton_method(:diff) { |_topic, **_args| {} }
    end
  end
end
