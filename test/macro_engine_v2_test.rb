# frozen_string_literal: true

require "test_helper"

class MacroEngineV2Test < Minitest::Test
  def setup
    @engine = TavernKit::Macro::V2::Engine.new(unknown: :keep)
  end

  def expand(text, vars = {})
    defaults = {
      user: "User",
      char: "Character",
    }

    @engine.expand(text, defaults.merge(vars))
  end

  # ---------------------------------------------------------------------------
  # MacroEngine.e2e.js (SillyTavern) parity tests (non-legacy)
  # ---------------------------------------------------------------------------

  def test_returns_input_unchanged_when_there_are_no_macros
    input = "Hello world, no macros here."
    assert_equal input, expand(input)
  end

  def test_evaluates_simple_macro_without_arguments
    input = "Start {{newline}} end."
    assert_equal "Start \n end.", expand(input)
  end

  def test_evaluates_multiple_macros_in_order
    input = "A {{setvar::test::4}}{{getvar::test}} B {{setvar::test::2}}{{getvar::test}} C"
    assert_equal "A 4 B 2 C", expand(input)
  end

  def test_handles_double_colon_separated_unnamed_argument
    input = "Reversed: {{reverse::abc}}!"
    assert_equal "Reversed: cba!", expand(input)
  end

  def test_handles_legacy_colon_separated_unnamed_argument
    input = "Reversed: {{reverse:abc}}!"
    assert_equal "Reversed: cba!", expand(input)
  end

  def test_handles_legacy_colon_separated_argument_as_one_even_with_more_separators_double_colon
    input = "Reversed: {{reverse:abc::def}}!"
    assert_equal "Reversed: fed::cba!", expand(input)
  end

  def test_handles_legacy_colon_separated_argument_as_one_even_with_more_separators_single_colon
    input = "Reversed: {{reverse:abc:def}}!"
    assert_equal "Reversed: fed:cba!", expand(input)
  end

  def test_handles_legacy_whitespace_separated_unnamed_argument
    input = "Values: {{roll 1d1}}!"
    assert_equal "Values: 1!", expand(input)
  end

  def test_handles_legacy_whitespace_separated_argument_as_one_even_with_more_separators
    input = "Values: {{reverse abc def}}!"
    assert_equal "Values: fed cba!", expand(input)
  end

  def test_supports_multiline_arguments_for_macros
    original = "first line\nsecond line"
    expected_reversed = original.chars.reverse.join

    input = "Result: {{reverse::#{original}}}"
    assert_equal "Result: #{expected_reversed}", expand(input)
  end

  def test_resolves_nested_macros_inside_arguments_inside_out
    input = "Result: {{setvar::test::0}}{{reverse::{{addvar::test::100}}{{getvar::test}}}}{{setvar::test::0}}"
    assert_equal "Result: 001", expand(input)
  end

  def test_resolves_nested_macros_across_multiple_arguments
    input = "Result: {{setvar::addvname::test}}{{addvar::{{getvar::addvname}}::{{setvar::test::5}}{{getvar::test}}}}{{getvar::test}}"
    assert_equal "Result: 10", expand(input)
  end

  def test_keeps_unknown_macro_syntax_but_resolves_nested_macros_inside_it
    input = "Test: {{unknown::{{newline}}}}"
    assert_equal "Test: {{unknown::\n}}", expand(input)
  end

  def test_keeps_surrounding_text_inside_unknown_macros_intact
    input = "Test: {{unknown::my {{newline}} example}}"
    assert_equal "Test: {{unknown::my \n example}}", expand(input)
  end

  def test_removes_comment_macros_with_simple_body
    input = "Hello{{// comment}}World"
    assert_equal "HelloWorld", expand(input)
  end

  def test_comment_macro_accepts_non_word_characters_immediately_after_double_slash
    input = "A{{//!@#$%^&*()_+}}B"
    assert_equal "AB", expand(input)
  end

  def test_comment_macro_ignores_additional_double_slashes_inside_body
    input = "X{{//comment with // extra // slashes}}Y"
    assert_equal "XY", expand(input)
  end

  def test_comment_macro_supports_multiline_bodies
    input = "Start{{// line one\nline two\nline three}}End"
    assert_equal "StartEnd", expand(input)
  end

  def test_allows_single_opening_brace_inside_macro_arguments
    input = "Test§ {{reverse::my { test}}"
    assert_equal "Test§ tset { ym", expand(input)
  end

  def test_allows_single_closing_brace_inside_macro_arguments
    input = "Test§ {{reverse::my } test}}"
    assert_equal "Test§ tset } ym", expand(input)
  end

  def test_treats_unterminated_macro_with_identifier_at_end_of_input_as_plain_text
    input = "Test {{ hehe"
    assert_equal input, expand(input)
  end

  def test_treats_invalid_macro_start_as_plain_text_when_followed_by_non_identifier_characters
    input = "Test {{§§ hehe"
    assert_equal input, expand(input)
  end

  def test_treats_unterminated_macro_in_the_middle_of_the_string_as_plain_text
    input = "Before {{ hehe After"
    assert_equal input, expand(input)
  end

  def test_treats_dangling_macro_start_as_text_and_still_evaluates_subsequent_macro
    input = "Test {{ hehe {{user}}"
    assert_equal "Test {{ hehe User", expand(input)
  end

  def test_ignores_invalid_macro_start_but_still_evaluates_following_valid_macro
    input = "Test {{&& hehe {{user}}"
    assert_equal "Test {{&& hehe User", expand(input)
  end

  def test_allows_single_opening_brace_immediately_before_a_macro
    input = "{{{char}}"
    assert_equal "{Character", expand(input)
  end

  def test_allows_single_closing_brace_immediately_after_a_macro
    input = "{{char}}}"
    assert_equal "Character}", expand(input)
  end

  def test_allows_single_braces_around_a_macro
    input = "{{{char}}}"
    assert_equal "{Character}", expand(input)
  end

  def test_allows_double_opening_braces_immediately_before_a_macro
    input = "{{{{char}}"
    assert_equal "{{Character", expand(input)
  end

  def test_allows_double_closing_braces_immediately_after_a_macro
    input = "{{char}}}}"
    assert_equal "Character}}", expand(input)
  end

  def test_allows_double_braces_around_a_macro
    input = "{{{{char}}}}"
    assert_equal "{{Character}}", expand(input)
  end

  def test_resolves_nested_macro_inside_argument_with_surrounding_braces
    input = "Result: {{reverse::pre-{ {{user}} }-post}}"
    assert_equal "Result: tsop-} resU {-erp", expand(input)
  end

  def test_handles_adjacent_macros_with_no_separator
    input = "{{char}}{{user}}"
    assert_equal "CharacterUser", expand(input)
  end

  def test_handles_macros_separated_only_by_surrounding_braces
    input = "{{char}}{ {{user}} }"
    assert_equal "Character{ User }", expand(input)
  end

  def test_handles_windows_newlines_with_braces_near_macros
    input = "Line1 {{char}}\r\n{Line2}"
    assert_equal "Line1 Character\r\n{Line2}", expand(input)
  end

  def test_treats_stray_closing_braces_outside_macros_as_plain_text
    input = "Foo }} bar"
    assert_equal input, expand(input)
  end

  def test_keeps_stray_closing_braces_and_still_evaluates_following_macro
    input = "Foo }} {{user}}"
    assert_equal "Foo }} User", expand(input)
  end

  def test_handles_stray_closing_braces_before_macros_as_plain_text
    input = "Foo {{user}} }}"
    assert_equal "Foo User }}", expand(input)
  end

  def test_pick_is_deterministic_for_same_seed_and_content
    input = "Choices: {{pick::red::green::blue}}, {{pick::red::green::blue}}."

    output1 = expand(input, pick_seed: 123_456)
    output2 = expand(input, pick_seed: 123_456)

    assert_equal output1, output2

    match = output1.match(/\AChoices: ([^,]+), ([^.]+)\.\z/)
    refute_nil match

    options = %w[red green blue]
    assert_includes options, match[1].strip
    assert_includes options, match[2].strip
  end

  def test_nested_macros_expand_inner_first
    vars = {
      inner: "X",
      outer: ->(inv) { "OUTER(#{inv.args})" },
    }

    assert_equal "OUTER(X)", expand("{{outer::{{inner}}}}", vars)
  end

  def test_unknown_macro_is_preserved_but_nested_macros_inside_expand
    assert_equal "{{unknown::Alice}}", expand("{{unknown::{{user}}}}", { user: "Alice" })
  end

  def test_escaped_macro_delimiter_outputs_literal_and_does_not_expand
    assert_equal "{{user}}", expand("\\{{user}}", { user: "Alice" })
  end

  def test_unescapes_single_braces_after_processing
    assert_equal "x{y}", expand("x\\{y\\}", {})
  end

  def test_trim_removes_itself_and_surrounding_newlines
    assert_equal "ab", expand("a\n\n{{trim}}\n\nb", {})
  end

  def test_pick_offset_uses_original_input_offset
    calls = 0
    vars = {
      varlen: ->(_inv) { (calls += 1).odd? ? "" : ("X" * 50) },
      pick: ->(inv) { inv.offset.to_s },
    }

    text = "{{varlen}}|{{pick::a,b}}"
    expected_offset = "{{varlen}}|".length

    assert_equal "|#{expected_offset}", expand(text, vars)
    assert_equal ("X" * 50) + "|#{expected_offset}", expand(text, vars)
  end
end
