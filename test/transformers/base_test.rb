# frozen_string_literal: true

require "test_helper"

class BaseTransformerTest < Minitest::Test
  def setup
    @transformer = FactDb::Transformers::Base.new
  end

  def test_transform_returns_input_unchanged
    result = FactDb::QueryResult.new(query: "test")
    result.add_facts([{ id: 1, text: "Test fact" }])

    transformed = @transformer.transform(result)

    assert_equal result, transformed
  end

  def test_get_value_from_hash_with_symbol_key
    obj = { name: "Paula Chen" }

    assert_equal "Paula Chen", @transformer.send(:get_value, obj, :name)
  end

  def test_get_value_from_hash_with_string_key
    obj = { "name" => "Paula Chen" }

    assert_equal "Paula Chen", @transformer.send(:get_value, obj, :name)
  end

  def test_get_value_from_object_with_method
    obj = Struct.new(:name).new("Paula Chen")

    assert_equal "Paula Chen", @transformer.send(:get_value, obj, :name)
  end

  def test_get_value_returns_nil_for_missing_key
    obj = { other: "value" }

    assert_nil @transformer.send(:get_value, obj, :name)
  end

  def test_format_date_with_date_object
    date = Date.new(2024, 1, 15)

    assert_equal "2024-01-15", @transformer.send(:format_date, date)
  end

  def test_format_date_with_time_object
    time = Time.new(2024, 1, 15, 10, 30, 0)

    assert_equal "2024-01-15", @transformer.send(:format_date, time)
  end

  def test_format_date_with_string
    str = "2024-01-15"

    assert_equal "2024-01-15", @transformer.send(:format_date, str)
  end

  def test_format_date_with_nil
    assert_nil @transformer.send(:format_date, nil)
  end

  def test_escape_string_with_quotes
    str = 'He said "hello"'

    assert_equal 'He said \"hello\"', @transformer.send(:escape_string, str)
  end

  def test_escape_string_with_newlines
    str = "Line one\nLine two"

    assert_equal 'Line one\nLine two', @transformer.send(:escape_string, str)
  end

  def test_to_variable_converts_to_lowercase
    assert_equal "paula_chen", @transformer.send(:to_variable, "Paula Chen")
  end

  def test_to_variable_removes_special_characters
    assert_equal "paula_chen_123", @transformer.send(:to_variable, "Paula Chen #123!")
  end

  def test_to_variable_strips_leading_trailing_underscores
    assert_equal "test", @transformer.send(:to_variable, "__test__")
  end

  def test_to_variable_truncates_to_30_characters
    long_name = "A" * 50
    result = @transformer.send(:to_variable, long_name)

    assert_equal 30, result.length
  end

  def test_truncate_short_string
    str = "Short"

    assert_equal "Short", @transformer.send(:truncate, str, 10)
  end

  def test_truncate_long_string
    str = "This is a very long string"

    assert_equal "This is...", @transformer.send(:truncate, str, 10)
  end

  def test_truncate_exact_length
    str = "ExactTen"

    assert_equal "ExactTen", @transformer.send(:truncate, str, 8)
  end
end
