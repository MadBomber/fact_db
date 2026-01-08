# frozen_string_literal: true

require "test_helper"

class TemporalQueriesIntegrationTest < Minitest::Test
  include FactDb::TestHelpers

  def setup
    super
    setup_employment_history
  end

  def test_current_employer_query
    clock = create_clock
    facts = clock.query_facts(entity: @paula.id, at: nil)

    assert_equal 1, facts.count
    assert_includes facts.first.fact_text, "Microsoft"
  end

  def test_employer_in_2022
    clock = create_clock

    # Query for mid-2022
    query_date = Date.new(2022, 6, 15)
    facts = clock.query_facts(entity: @paula.id, at: query_date)

    assert_equal 1, facts.count
    assert_includes facts.first.fact_text, "Google"
  end

  def test_employer_in_2021
    clock = create_clock

    # Query for 2021 - should find Google fact
    query_date = Date.new(2021, 6, 15)
    facts = clock.query_facts(entity: @paula.id, at: query_date)

    assert facts.any?
    assert_includes facts.first.fact_text, "Google"
  end

  def test_no_employer_in_2019
    clock = create_clock

    # Query for 2019 - before Paula joined Google
    query_date = Date.new(2019, 6, 15)
    facts = clock.query_facts(entity: @paula.id, at: query_date)

    assert facts.empty?
  end

  def test_timeline_building
    clock = create_clock
    timeline = clock.timeline_for(@paula.id)

    events = timeline.to_a

    # Should have 2 events: Google then Microsoft
    assert_equal 2, events.count

    # First event should be Google
    assert_includes events.first.fact_text, "Google"

    # Last event should be Microsoft
    assert_includes events.last.fact_text, "Microsoft"
  end

  def test_timeline_active_facts
    clock = create_clock
    timeline = clock.timeline_for(@paula.id)

    active = timeline.active

    # Only Microsoft should be active
    assert_equal 1, active.count
    assert_includes active.first.fact_text, "Microsoft"
  end

  def test_timeline_historical_facts
    clock = create_clock
    timeline = clock.timeline_for(@paula.id)

    historical = timeline.historical

    # Only Google should be historical
    assert_equal 1, historical.count
    assert_includes historical.first.fact_text, "Google"
  end

  def test_timeline_state_at_date
    clock = create_clock
    timeline = clock.timeline_for(@paula.id)

    # Check state in 2022
    state_2022 = timeline.state_at(Date.new(2022, 6, 15))

    assert_equal 1, state_2022.count
    assert_includes state_2022.first.fact_text, "Google"
  end

  private

  def setup_employment_history
    @paula = create_entity(name: "Paula Chen", type: "person")
    @google = create_entity(name: "Google", type: "organization")
    @microsoft = create_entity(name: "Microsoft", type: "organization")

    # Paula worked at Google from 2020-01-15 to 2024-03-14
    @google_fact = create_fact(
      text: "Paula Chen works at Google",
      valid_at: Date.new(2020, 1, 15),
      invalid_at: Date.new(2024, 3, 14),
      status: "canonical"
    )
    @google_fact.add_mention(entity: @paula, text: "Paula Chen", role: "subject")
    @google_fact.add_mention(entity: @google, text: "Google", role: "object")

    # Paula works at Microsoft from 2024-03-15 (ongoing)
    @microsoft_fact = create_fact(
      text: "Paula Chen works at Microsoft",
      valid_at: Date.new(2024, 3, 15),
      invalid_at: nil,
      status: "canonical"
    )
    @microsoft_fact.add_mention(entity: @paula, text: "Paula Chen", role: "subject")
    @microsoft_fact.add_mention(entity: @microsoft, text: "Microsoft", role: "object")
  end
end
