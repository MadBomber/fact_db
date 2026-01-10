# frozen_string_literal: true

require "test_helper"

class CypherTransformerTest < Minitest::Test
  def setup
    @transformer = FactDb::Transformers::CypherTransformer.new
  end

  def test_transform_empty_result
    result = FactDb::QueryResult.new(query: "test")

    output = @transformer.transform(result)

    assert_equal "", output
  end

  def test_transform_entities_to_nodes
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => { id: 1, canonical_name: "Paula Chen", entity_type: "person" }
    })

    output = @transformer.transform(result)

    assert_includes output, "(paula_chen:Person {name: \"Paula Chen\"})"
  end

  def test_transform_entity_with_aliases
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => {
        id: 1,
        canonical_name: "Paula Chen",
        entity_type: "person",
        aliases: [{ alias_text: "PC" }, { alias_text: "Paula" }]
      }
    })

    output = @transformer.transform(result)

    assert_includes output, "aliases: [\"PC\", \"Paula\"]"
  end

  def test_transform_facts_to_relationships
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => { id: 1, canonical_name: "Paula Chen", entity_type: "person" },
      2 => { id: 2, canonical_name: "Microsoft", entity_type: "organization" }
    })
    result.add_facts([{
      id: 1,
      fact_text: "Paula Chen works at Microsoft",
      valid_at: Date.new(2024, 1, 10),
      status: "canonical",
      entity_mentions: [
        { entity_id: 1, mention_role: "subject" },
        { entity_id: 2, mention_role: "object" }
      ]
    }])

    output = @transformer.transform(result)

    assert_includes output, "paula_chen"
    assert_includes output, "microsoft"
    assert_includes output, "WORKS_AT"
  end

  def test_extract_relationship_type_works_at
    assert_equal "WORKS_AT", @transformer.send(:extract_relationship_type, "Paula works at Microsoft")
    assert_equal "WORKS_AT", @transformer.send(:extract_relationship_type, "She works for Google")
  end

  def test_extract_relationship_type_worked_at
    assert_equal "WORKED_AT", @transformer.send(:extract_relationship_type, "Paula worked at Google")
    assert_equal "WORKED_AT", @transformer.send(:extract_relationship_type, "She worked for Amazon")
  end

  def test_extract_relationship_type_reports_to
    assert_equal "REPORTS_TO", @transformer.send(:extract_relationship_type, "Paula reports to John")
  end

  def test_extract_relationship_type_is_a
    assert_equal "IS_A", @transformer.send(:extract_relationship_type, "Paula is a engineer")
    assert_equal "IS_A", @transformer.send(:extract_relationship_type, "She is the manager")
  end

  def test_extract_relationship_type_has
    assert_equal "HAS", @transformer.send(:extract_relationship_type, "Paula has a degree")
  end

  def test_extract_relationship_type_decided
    assert_equal "DECIDED", @transformer.send(:extract_relationship_type, "The committee decided to proceed")
  end

  def test_extract_relationship_type_joined
    assert_equal "JOINED", @transformer.send(:extract_relationship_type, "Paula joined in January")
  end

  def test_extract_relationship_type_left
    assert_equal "LEFT", @transformer.send(:extract_relationship_type, "Paula left in December")
  end

  def test_extract_relationship_type_default
    assert_equal "RELATES_TO", @transformer.send(:extract_relationship_type, "Paula something Microsoft")
  end

  def test_format_props_empty
    assert_equal "{}", @transformer.send(:format_props, {})
  end

  def test_format_props_with_string
    props = { name: "Paula" }

    assert_equal "{name: \"Paula\"}", @transformer.send(:format_props, props)
  end

  def test_format_props_with_array
    props = { aliases: ["PC", "Paula"] }

    assert_equal "{aliases: [\"PC\", \"Paula\"]}", @transformer.send(:format_props, props)
  end

  def test_format_props_with_nil
    props = { value: nil }

    assert_equal "{value: null}", @transformer.send(:format_props, props)
  end

  def test_format_props_with_number
    props = { confidence: 0.95 }

    assert_equal "{confidence: 0.95}", @transformer.send(:format_props, props)
  end

  def test_relationship_includes_temporal_props
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => { id: 1, canonical_name: "Paula Chen", entity_type: "person" },
      2 => { id: 2, canonical_name: "Microsoft", entity_type: "organization" }
    })
    result.add_facts([{
      id: 1,
      fact_text: "Paula Chen works at Microsoft",
      valid_at: Date.new(2024, 1, 10),
      invalid_at: Date.new(2024, 6, 15),
      status: "superseded",
      confidence: 0.95,
      entity_mentions: [
        { entity_id: 1, mention_role: "subject" },
        { entity_id: 2, mention_role: "object" }
      ]
    }])

    output = @transformer.transform(result)

    assert_includes output, "since: \"2024-01-10\""
    assert_includes output, "until: \"2024-06-15\""
    assert_includes output, "status: \"superseded\""
    assert_includes output, "confidence: 0.95"
  end
end
