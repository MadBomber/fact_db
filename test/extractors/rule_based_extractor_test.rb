# frozen_string_literal: true

require "test_helper"

class RuleBasedExtractorTest < Minitest::Test
  include FactDb::TestHelpers

  def setup
    super
    @extractor = FactDb::Extractors::RuleBasedExtractor.new
  end

  def test_extract_employment_fact
    text = "Paula Chen works at Microsoft"
    facts = @extractor.extract(text)

    assert_equal 1, facts.length

    fact = facts.first
    assert_match(/Paula Chen.*Microsoft/i, fact[:text])
    assert_equal 2, fact[:mentions].length

    person_mention = fact[:mentions].find { |m| m[:kind] == "person" }
    org_mention = fact[:mentions].find { |m| m[:kind] == "organization" }

    assert_equal "Paula Chen", person_mention[:name]
    assert_equal "subject", person_mention[:role]
    assert_equal "Microsoft", org_mention[:name]
    assert_equal "object", org_mention[:role]
  end

  def test_extract_employment_with_role
    text = "Paula Chen is a Principal Engineer at Microsoft"
    facts = @extractor.extract(text)

    assert facts.any?
  end

  def test_extract_employment_with_date
    text = "Paula Chen joined Microsoft on January 10, 2024"
    facts = @extractor.extract(text, captured_at: Time.current)

    assert facts.any?
    fact = facts.first
    assert fact[:valid_at].present?
    assert_equal Date.new(2024, 1, 10), fact[:valid_at].to_date
  end

  def test_extract_location_fact
    text = "Paula Chen lives in Seattle"
    facts = @extractor.extract(text)

    assert facts.any?
    fact = facts.first

    person_mention = fact[:mentions].find { |m| m[:kind] == "person" }
    place_mention = fact[:mentions].find { |m| m[:kind] == "place" }

    assert_equal "Paula Chen", person_mention[:name]
    assert_equal "Seattle", place_mention[:name]
    assert_equal "location", place_mention[:role]
  end

  def test_extract_entities
    text = "Paula Chen and John Smith work at Microsoft and Google"
    entities = @extractor.extract_entities(text)

    names = entities.map { |e| e[:name] }

    assert_includes names, "Paula Chen"
    assert_includes names, "John Smith"
  end

  def test_empty_text_returns_empty_array
    assert_equal [], @extractor.extract("")
    assert_equal [], @extractor.extract(nil)
  end

  def test_extraction_method
    assert_equal "rule_based", @extractor.extraction_method
  end
end
