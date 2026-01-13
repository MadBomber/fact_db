# frozen_string_literal: true

require "test_helper"

class AliasFilterTest < Minitest::Test
  def test_rejects_nil
    refute FactDb::Validation::AliasFilter.valid?(nil)
  end

  def test_rejects_empty_string
    refute FactDb::Validation::AliasFilter.valid?("")
    refute FactDb::Validation::AliasFilter.valid?("   ")
  end

  def test_rejects_short_strings
    refute FactDb::Validation::AliasFilter.valid?("a")
    refute FactDb::Validation::AliasFilter.valid?("x")
  end

  def test_rejects_pronouns
    pronouns = %w[he she him her they them his their it we you I me my]
    pronouns.each do |pronoun|
      refute FactDb::Validation::AliasFilter.valid?(pronoun), "Should reject pronoun: #{pronoun}"
    end
  end

  def test_rejects_generic_terms
    generic_terms = %w[man woman person people husband wife the a an]
    generic_terms.each do |term|
      refute FactDb::Validation::AliasFilter.valid?(term), "Should reject generic term: #{term}"
    end
  end

  def test_rejects_generic_role_references
    roles = ["the man", "this person", "a woman", "the husband", "believers", "disciples"]
    roles.each do |role|
      refute FactDb::Validation::AliasFilter.valid?(role), "Should reject generic role: #{role}"
    end
  end

  def test_accepts_proper_names
    names = ["Jesus Christ", "Simon Peter", "Paul the Apostle", "Mary Magdalene"]
    names.each do |name|
      assert FactDb::Validation::AliasFilter.valid?(name), "Should accept proper name: #{name}"
    end
  end

  def test_accepts_titles_and_nicknames
    aliases = ["Dr. Smith", "Captain Kirk", "the Apostle Paul", "Saul of Tarsus"]
    aliases.each do |a|
      assert FactDb::Validation::AliasFilter.valid?(a), "Should accept title/nickname: #{a}"
    end
  end

  def test_rejects_ambiguous_standalone_first_names
    # "Simon" alone should be rejected when the canonical name is different
    refute FactDb::Validation::AliasFilter.valid?("Simon", name: "Jesus")
    refute FactDb::Validation::AliasFilter.valid?("Peter", name: "Jesus")
    refute FactDb::Validation::AliasFilter.valid?("John", name: "Jesus")
  end

  def test_accepts_first_name_matching_canonical
    # "Simon" should be accepted if canonical name starts with Simon
    assert FactDb::Validation::AliasFilter.valid?("Simon", name: "Simon Peter")
    assert FactDb::Validation::AliasFilter.valid?("John", name: "John Mark")

    # "Peter" with canonical_name "Peter" is rejected because it matches canonical
    refute FactDb::Validation::AliasFilter.valid?("Peter", name: "Peter")
  end

  def test_accepts_multi_word_names_with_common_first_names
    # "Simon Peter" should be accepted even though "Simon" alone wouldn't be
    assert FactDb::Validation::AliasFilter.valid?("Simon Peter")
    assert FactDb::Validation::AliasFilter.valid?("John Mark")
  end

  def test_filter_removes_invalid_aliases
    aliases = ["him", "Jesus Christ", "he", "Lord Jesus", "they", "Christ the Lord"]
    filtered = FactDb::Validation::AliasFilter.filter(aliases)

    assert_includes filtered, "Jesus Christ"
    assert_includes filtered, "Lord Jesus"
    assert_includes filtered, "Christ the Lord"
    refute_includes filtered, "him"
    refute_includes filtered, "he"
    refute_includes filtered, "they"
  end

  def test_rejects_generic_role_the_lord
    # "the Lord" is a generic role reference and should be rejected
    refute FactDb::Validation::AliasFilter.valid?("the Lord")
  end

  def test_filter_deduplicates_case_insensitively
    aliases = ["Jesus", "JESUS", "jesus"]
    filtered = FactDb::Validation::AliasFilter.filter(aliases)

    assert_equal 1, filtered.length
  end

  def test_rejection_reason_for_pronoun
    assert_equal "is a pronoun", FactDb::Validation::AliasFilter.rejection_reason("him")
  end

  def test_rejection_reason_for_generic_term
    assert_equal "is a generic term", FactDb::Validation::AliasFilter.rejection_reason("man")
  end

  def test_rejection_reason_for_ambiguous_name
    reason = FactDb::Validation::AliasFilter.rejection_reason("Simon", name: "Jesus")
    assert_equal "is an ambiguous standalone first name", reason
  end

  def test_rejection_reason_returns_nil_for_valid_alias
    assert_nil FactDb::Validation::AliasFilter.rejection_reason("Jesus Christ")
  end
end
