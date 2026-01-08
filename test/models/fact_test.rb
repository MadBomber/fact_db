# frozen_string_literal: true

require "test_helper"

class FactTest < Minitest::Test
  include FactDb::TestHelpers

  def test_temporal_validity_current
    fact = create_fact(valid_at: 1.year.ago, invalid_at: nil)

    assert fact.currently_valid?
    assert fact.valid_at?(Time.current)
    assert fact.valid_at?(6.months.ago)
  end

  def test_temporal_validity_historical
    fact = create_fact(valid_at: 2.years.ago, invalid_at: 1.year.ago)

    refute fact.currently_valid?
    refute fact.valid_at?(Time.current)
    assert fact.valid_at?(18.months.ago)
    refute fact.valid_at?(6.months.ago)
  end

  def test_duration_calculation
    fact = create_fact(valid_at: 100.days.ago, invalid_at: 10.days.ago)

    assert_equal 90, fact.duration_days
  end

  def test_duration_nil_for_current_facts
    fact = create_fact(valid_at: 1.year.ago, invalid_at: nil)

    assert_nil fact.duration_days
  end

  def test_fact_statuses
    canonical = create_fact(status: "canonical")
    superseded = create_fact(status: "superseded")
    synthesized = create_fact(status: "synthesized")

    assert canonical.status == "canonical"
    refute canonical.superseded?
    refute canonical.synthesized?

    assert superseded.superseded?
    assert synthesized.synthesized?
  end

  def test_scopes_currently_valid
    current = create_fact(valid_at: 1.day.ago, invalid_at: nil)
    historical = create_fact(valid_at: 1.year.ago, invalid_at: 1.month.ago)

    results = FactDb::Models::Fact.currently_valid

    assert_includes results, current
    refute_includes results, historical
  end

  def test_scopes_valid_at_date
    fact1 = create_fact(
      text: "Fact during period",
      valid_at: 2.years.ago,
      invalid_at: 6.months.ago
    )
    fact2 = create_fact(
      text: "Fact after period",
      valid_at: 3.months.ago,
      invalid_at: nil
    )

    query_date = 1.year.ago
    results = FactDb::Models::Fact.valid_at(query_date)

    assert_includes results, fact1
    refute_includes results, fact2
  end

  def test_supersession
    old_fact = create_fact(text: "Paula works at Google")
    new_fact = old_fact.supersede_with!("Paula works at Microsoft", valid_at: Time.current)

    old_fact.reload

    assert_equal "superseded", old_fact.status
    assert_equal new_fact.id, old_fact.superseded_by_id
    assert_equal "canonical", new_fact.status
    assert old_fact.invalid_at.present?
  end

  def test_invalidation
    fact = create_fact(valid_at: 1.year.ago, invalid_at: nil)

    assert fact.currently_valid?

    fact.invalidate!(at: 1.day.ago)

    refute fact.currently_valid?
    assert fact.invalid_at.present?
  end

  def test_fact_hash_generation
    fact = FactDb::Models::Fact.new(fact_text: "Test assertion", valid_at: Time.current)
    fact.valid?

    assert fact.fact_hash.present?
    assert_equal 64, fact.fact_hash.length
  end
end
