# frozen_string_literal: true

require "test_helper"

class FactServiceTest < Minitest::Test
  include FactDb::TestHelpers

  def setup
    super
    @config = FactDb.config
    @service = FactDb::Services::FactService.new(@config)
  end

  def test_fact_stats_returns_counts_by_status
    create_fact(text: "Canonical fact 1", status: "canonical")
    create_fact(text: "Canonical fact 2", status: "canonical")
    create_fact(text: "Superseded fact", status: "superseded")
    create_fact(text: "Synthesized fact", status: "synthesized")

    stats = @service.fact_stats

    assert_equal 2, stats[:canonical]
    assert_equal 1, stats[:superseded]
    assert_equal 1, stats[:synthesized]
    assert_equal 0, stats[:corroborated]
  end

  def test_fact_stats_for_specific_entity
    entity = create_entity(name: "Paula Chen", type: "person")
    other_entity = create_entity(name: "Microsoft", type: "organization")

    fact1 = create_fact(text: "Paula Chen joined", status: "canonical")
    fact2 = create_fact(text: "Paula Chen promoted", status: "canonical")
    fact3 = create_fact(text: "Microsoft hired people", status: "canonical")
    fact4 = create_fact(text: "Paula old role", status: "superseded")

    FactDb::Models::EntityMention.create!(
      fact: fact1,
      entity: entity,
      mention_role: "subject",
      mention_text: "Paula Chen"
    )
    FactDb::Models::EntityMention.create!(
      fact: fact2,
      entity: entity,
      mention_role: "subject",
      mention_text: "Paula Chen"
    )
    FactDb::Models::EntityMention.create!(
      fact: fact3,
      entity: other_entity,
      mention_role: "subject",
      mention_text: "Microsoft"
    )
    FactDb::Models::EntityMention.create!(
      fact: fact4,
      entity: entity,
      mention_role: "subject",
      mention_text: "Paula Chen"
    )

    stats = @service.fact_stats(entity.id)

    assert_equal 2, stats[:canonical]
    assert_equal 1, stats[:superseded]
    assert_equal 0, stats[:synthesized]
  end

  def test_fact_stats_counts_corroborated
    fact = create_fact(text: "Corroborated fact", status: "canonical")
    fact.update!(corroborated_by_ids: [100, 101])

    stats = @service.fact_stats

    assert_equal 1, stats[:corroborated]
  end

  def test_fact_stats_with_no_facts
    stats = @service.fact_stats

    assert_equal 0, stats[:canonical]
    assert_equal 0, stats[:superseded]
    assert_equal 0, stats[:synthesized]
    assert_equal 0, stats[:corroborated]
  end
end
