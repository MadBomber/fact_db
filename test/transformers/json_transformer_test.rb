# frozen_string_literal: true

require "test_helper"

class JsonTransformerTest < Minitest::Test
  def setup
    @transformer = FactDb::Transformers::JsonTransformer.new
  end

  def test_transform_returns_hash
    result = FactDb::QueryResult.new(query: "test")

    output = @transformer.transform(result)

    assert_instance_of Hash, output
  end

  def test_transform_includes_query
    result = FactDb::QueryResult.new(query: "Paula Chen")

    output = @transformer.transform(result)

    assert_equal "Paula Chen", output[:query]
  end

  def test_transform_includes_facts
    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([{ id: 1, fact_text: "Test fact" }])

    output = @transformer.transform(result)

    assert_equal 1, output[:facts].size
    assert_equal "Test fact", output[:facts].first[:fact_text]
  end

  def test_transform_includes_entities
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => { id: 1, canonical_name: "Paula Chen" }
    })

    output = @transformer.transform(result)

    assert_equal 1, output[:entities].size
    assert_equal "Paula Chen", output[:entities][1][:canonical_name]
  end

  def test_transform_includes_metadata
    Timecop.freeze(Time.local(2024, 6, 15, 12, 0, 0)) do
      result = FactDb::QueryResult.new(query: "test")

      output = @transformer.transform(result)

      assert output[:metadata][:retrieved_at]
      assert_equal [:fact_db], output[:metadata][:stores_queried]
    end
  end
end
