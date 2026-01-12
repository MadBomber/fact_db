# frozen_string_literal: true

require "test_helper"

class TextTransformerTest < Minitest::Test
  def setup
    @transformer = FactDb::Transformers::TextTransformer.new
  end

  def test_transform_empty_result
    result = FactDb::QueryResult.new(query: "Paula Chen")

    output = @transformer.transform(result)

    assert_equal "No results found for query: Paula Chen", output
  end

  def test_transform_entities_section
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => { id: 1, name: "Paula Chen", type: "person" }
    })
    result.add_facts([{ id: 1, text: "Test", status: "canonical" }])

    output = @transformer.transform(result)

    assert_includes output, "## Entities"
    assert_includes output, "**Paula Chen**"
    assert_includes output, "(person)"
  end

  def test_transform_entity_with_aliases
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => {
        id: 1,
        name: "Paula Chen",
        type: "person",
        aliases: [{ name: "PC" }, { name: "Paula" }]
      }
    })
    result.add_facts([{ id: 1, text: "Test", status: "canonical" }])

    output = @transformer.transform(result)

    assert_includes output, "also known as: PC, Paula"
  end

  def test_transform_facts_section
    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([
      { id: 1, text: "Paula works at Microsoft", status: "canonical" }
    ])

    output = @transformer.transform(result)

    assert_includes output, "## Facts"
    assert_includes output, "Paula works at Microsoft"
  end

  def test_transform_groups_by_status
    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([
      { id: 1, text: "Current fact", status: "canonical" },
      { id: 2, text: "Old fact", status: "superseded" },
      { id: 3, text: "Verified fact", status: "corroborated" }
    ])

    output = @transformer.transform(result)

    assert_includes output, "### Current Facts"
    assert_includes output, "### Historical Facts (Superseded)"
    assert_includes output, "### Corroborated Facts"
  end

  def test_transform_includes_temporal_info
    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([{
      id: 1,
      text: "Paula works at Microsoft",
      status: "canonical",
      valid_at: Date.new(2024, 1, 10),
      invalid_at: Date.new(2024, 6, 15)
    }])

    output = @transformer.transform(result)

    assert_includes output, "from 2024-01-10"
    assert_includes output, "until 2024-06-15"
  end

  def test_transform_includes_confidence
    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([{
      id: 1,
      text: "Paula works at Microsoft",
      status: "canonical",
      confidence: 0.95
    }])

    output = @transformer.transform(result)

    assert_includes output, "[confidence: 95%]"
  end

  def test_transform_synthesized_section
    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([
      { id: 1, text: "Synthesized fact", status: "synthesized" }
    ])

    output = @transformer.transform(result)

    assert_includes output, "### Synthesized Facts"
    assert_includes output, "Synthesized fact"
  end
end
