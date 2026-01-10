# frozen_string_literal: true

require "test_helper"

class TripleTransformerTest < Minitest::Test
  def setup
    @transformer = FactDb::Transformers::TripleTransformer.new
  end

  def test_transform_empty_result
    result = FactDb::QueryResult.new(query: "test")

    output = @transformer.transform(result)

    assert_equal [], output
  end

  def test_transform_entity_to_type_triple
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => { id: 1, canonical_name: "Paula Chen", entity_type: "person" }
    })

    output = @transformer.transform(result)

    assert_includes output, ["Paula Chen", "type", "Person"]
  end

  def test_transform_entity_aliases
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => {
        id: 1,
        canonical_name: "Paula Chen",
        entity_type: "person",
        aliases: [{ alias_text: "PC" }]
      }
    })

    output = @transformer.transform(result)

    assert_includes output, ["Paula Chen", "also_known_as", "PC"]
  end

  def test_transform_entity_resolution_status
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => {
        id: 1,
        canonical_name: "Paula Chen",
        entity_type: "person",
        resolution_status: "resolved"
      }
    })

    output = @transformer.transform(result)

    assert_includes output, ["Paula Chen", "resolution_status", "resolved"]
  end

  def test_transform_fact_to_triples
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => { id: 1, canonical_name: "Paula Chen", entity_type: "person" }
    })
    result.add_facts([{
      id: 1,
      fact_text: "Paula Chen is a engineer",
      entity_mentions: [{ entity_id: 1, mention_role: "subject" }]
    }])

    output = @transformer.transform(result)

    main_triples = output.select { |t| t[1] == "is" }
    assert_equal 1, main_triples.size
    assert_equal "Paula Chen", main_triples.first[0]
  end

  def test_transform_fact_with_temporal_metadata
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => { id: 1, canonical_name: "Paula Chen", entity_type: "person" }
    })
    result.add_facts([{
      id: 1,
      fact_text: "Paula Chen is a engineer",
      valid_at: Date.new(2024, 1, 10),
      invalid_at: Date.new(2024, 6, 15),
      status: "superseded",
      confidence: 0.95,
      entity_mentions: [{ entity_id: 1, mention_role: "subject" }]
    }])

    output = @transformer.transform(result)

    valid_from_triples = output.select { |t| t[1].include?("valid_from") }
    assert_equal 1, valid_from_triples.size
    assert_equal "2024-01-10", valid_from_triples.first[2]

    valid_until_triples = output.select { |t| t[1].include?("valid_until") }
    assert_equal 1, valid_until_triples.size

    status_triples = output.select { |t| t[1].include?("status") && !t[1].include?("resolution") }
    assert_equal 1, status_triples.size
    assert_equal "superseded", status_triples.first[2]

    confidence_triples = output.select { |t| t[1].include?("confidence") }
    assert_equal 1, confidence_triples.size
  end

  def test_extract_subject_from_fact_text
    subject = @transformer.send(:extract_subject, "Paula Chen is a engineer")

    assert_equal "Paula Chen", subject
  end

  def test_extract_subject_handles_various_verbs
    assert_equal "Paula Chen", @transformer.send(:extract_subject, "Paula Chen works at Microsoft")
    assert_equal "Paula Chen", @transformer.send(:extract_subject, "Paula Chen has a degree")
    assert_equal "The team", @transformer.send(:extract_subject, "The team was successful")
  end

  def test_extract_predicate_object_is
    predicate, object = @transformer.send(:extract_predicate_object, "Paula Chen is a engineer", "Paula Chen")

    assert_equal "is", predicate
    assert_equal "a engineer", object
  end

  def test_extract_predicate_object_has
    predicate, object = @transformer.send(:extract_predicate_object, "Paula Chen has a degree", "Paula Chen")

    assert_equal "has", predicate
    assert_equal "a degree", object
  end

  def test_extract_predicate_object_works
    predicate, object = @transformer.send(:extract_predicate_object, "Paula Chen works at Microsoft", "Paula Chen")

    assert_equal "works_at", predicate
    assert_equal "at Microsoft", object
  end

  def test_extract_predicate_object_default
    predicate, object = @transformer.send(:extract_predicate_object, "Paula Chen something else", "Paula Chen")

    assert_equal "asserts", predicate
    assert_equal "something else", object
  end

  def test_transform_fact_with_other_entity_mentions
    result = FactDb::QueryResult.new(query: "test")
    result.instance_variable_set(:@entities, {
      1 => { id: 1, canonical_name: "Paula Chen", entity_type: "person" },
      2 => { id: 2, canonical_name: "Microsoft", entity_type: "organization" }
    })
    result.add_facts([{
      id: 1,
      fact_text: "Paula Chen works at Microsoft",
      entity_mentions: [
        { entity_id: 1, mention_role: "subject" },
        { entity_id: 2, mention_role: "object" }
      ]
    }])

    output = @transformer.transform(result)

    object_triples = output.select { |t| t[1] == "object" }
    assert_equal 1, object_triples.size
    assert_equal "Paula Chen", object_triples.first[0]
    assert_equal "Microsoft", object_triples.first[2]
  end
end
