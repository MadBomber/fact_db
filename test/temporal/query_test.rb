# frozen_string_literal: true

require "test_helper"

class TemporalQueryTest < Minitest::Test
  include FactDb::TestHelpers

  def setup
    super
    @query = FactDb::Temporal::Query.new
  end

  def test_query_currently_valid_facts
    current = create_fact(valid_at: 1.day.ago, invalid_at: nil, status: "canonical")
    historical = create_fact(valid_at: 1.year.ago, invalid_at: 1.month.ago, status: "canonical")

    results = @query.execute(at: nil, status: :canonical)

    assert_includes results, current
    refute_includes results, historical
  end

  def test_query_facts_at_specific_date
    # Fact valid from 2 years ago to 6 months ago
    fact1 = create_fact(
      text: "Paula works at Google",
      valid_at: 2.years.ago,
      invalid_at: 6.months.ago,
      status: "canonical"
    )

    # Fact valid from 3 months ago to now
    fact2 = create_fact(
      text: "Paula works at Microsoft",
      valid_at: 3.months.ago,
      invalid_at: nil,
      status: "canonical"
    )

    # Query for 1 year ago
    results = @query.execute(at: 1.year.ago, status: :canonical)

    assert_includes results, fact1
    refute_includes results, fact2
  end

  def test_query_by_entity
    paula = create_entity(name: "Paula Chen", type: "person")
    john = create_entity(name: "John Smith", type: "person")

    paula_fact = create_fact(text: "Paula works at Google")
    john_fact = create_fact(text: "John works at Microsoft")

    paula_fact.add_mention(entity: paula, text: "Paula", role: "subject")
    john_fact.add_mention(entity: john, text: "John", role: "subject")

    results = @query.execute(entity_id: paula.id, status: :canonical)

    assert_includes results, paula_fact
    refute_includes results, john_fact
  end

  def test_query_canonical_only
    canonical = create_fact(status: "canonical")
    superseded = create_fact(status: "superseded")

    results = @query.execute(status: :canonical)

    assert_includes results, canonical
    refute_includes results, superseded
  end

  def test_current_facts_helper
    current = create_fact(valid_at: 1.day.ago, invalid_at: nil, status: "canonical")
    historical = create_fact(valid_at: 1.year.ago, invalid_at: 1.month.ago, status: "canonical")

    entity = create_entity(name: "Paula")
    current.add_mention(entity: entity, text: "Paula", role: "subject")
    historical.add_mention(entity: entity, text: "Paula", role: "subject")

    results = @query.current_facts(entity_id: entity.id)

    assert_includes results, current
    refute_includes results, historical
  end

  def test_diff_between_dates
    entity = create_entity(name: "Paula", type: "person")

    # Fact valid from 2 years ago, still valid
    long_running = create_fact(
      text: "Paula lives in Seattle",
      valid_at: 2.years.ago,
      invalid_at: nil
    )
    long_running.add_mention(entity: entity, text: "Paula", role: "subject")

    # Fact valid from 2 years ago to 6 months ago
    old_fact = create_fact(
      text: "Paula works at Google",
      valid_at: 2.years.ago,
      invalid_at: 6.months.ago
    )
    old_fact.add_mention(entity: entity, text: "Paula", role: "subject")

    # Fact valid from 3 months ago
    new_fact = create_fact(
      text: "Paula works at Microsoft",
      valid_at: 3.months.ago,
      invalid_at: nil
    )
    new_fact.add_mention(entity: entity, text: "Paula", role: "subject")

    diff = @query.diff(entity_id: entity.id, from_date: 1.year.ago, to_date: Time.current)

    assert_includes diff[:removed], old_fact
    assert_includes diff[:added], new_fact
    assert_includes diff[:unchanged], long_running
  end
end
