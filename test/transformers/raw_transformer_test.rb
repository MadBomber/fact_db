# frozen_string_literal: true

require "test_helper"

# Mock fact object that behaves like an ActiveRecord model
MockFact = Struct.new(:id, :text, :valid_at, :invalid_at, :status, :confidence, :entity_mentions, keyword_init: true) do
  def as_json
    to_h
  end
end

class RawTransformerTest < Minitest::Test
  def setup
    @transformer = FactDb::Transformers::RawTransformer.new
  end

  def test_transform_returns_array
    result = FactDb::QueryResult.new(query: "test")

    output = @transformer.transform(result)

    assert_instance_of Array, output
  end

  def test_transform_returns_empty_array_when_no_facts
    result = FactDb::QueryResult.new(query: "Nobody")

    output = @transformer.transform(result)

    assert_equal [], output
  end

  def test_transform_returns_raw_facts_unchanged
    raw_facts = [
      { id: 1, text: "Paula works at Microsoft" },
      { id: 2, text: "Paula is a Principal Engineer" }
    ]

    result = FactDb::QueryResult.new(query: "Paula")
    result.add_facts(raw_facts)

    output = @transformer.transform(result)

    assert_equal 2, output.size
    assert_equal raw_facts, output
  end

  def test_transform_preserves_original_objects
    mock_fact = MockFact.new(
      id: 1,
      text: "Test fact",
      valid_at: Date.new(2024, 1, 10),
      status: "canonical"
    )

    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([mock_fact])

    output = @transformer.transform(result)

    assert_equal 1, output.length
    assert_same mock_fact, output.first
    assert_instance_of MockFact, output.first
  end

  def test_transform_does_not_normalize_facts
    mock_fact = MockFact.new(
      id: 42,
      text: "Original fact text",
      valid_at: Date.new(2024, 6, 15),
      status: "canonical"
    )

    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([mock_fact])

    output = @transformer.transform(result)

    # Raw transformer should return the original object, not a normalized hash
    assert_respond_to output.first, :text
    assert_equal "Original fact text", output.first.text
  end
end
