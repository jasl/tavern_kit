# frozen_string_literal: true

require "test_helper"
require "tavern_kit/lore/engine"
require "tavern_kit/lore/book"
require "tavern_kit/lore/entry"
require "tavern_kit/lore/decorator_parser"

class CCv3ComplianceTest < Minitest::Test
  # ---------------------------------------------------------------------------
  # DecoratorParser Tests
  # ---------------------------------------------------------------------------

  def test_decorator_parser_extracts_simple_decorators
    parser = TavernKit::Lore::DecoratorParser.new
    result = parser.parse("@@depth 4\n@@role user\n\nActual content here")

    assert_equal 4, result[:decorators][:depth]
    assert_equal "user", result[:decorators][:role]  # Role is returned as string
    assert_equal "Actual content here", result[:content]
  end

  def test_decorator_parser_handles_fallback_decorators
    parser = TavernKit::Lore::DecoratorParser.new
    result = parser.parse("@@@depth 2\n@@@role assistant\n\nFallback content")

    assert_equal 2, result[:fallback_decorators][:depth]
    assert_equal "assistant", result[:fallback_decorators][:role]  # Role is returned as string
    assert_equal "Fallback content", result[:content]
  end

  def test_decorator_parser_handles_boolean_decorators
    parser = TavernKit::Lore::DecoratorParser.new
    # Flag decorators like constant/use_regex return true when present (value is ignored)
    result = parser.parse("@@constant\n@@use_regex\n\nContent")

    assert_equal true, result[:decorators][:constant]
    assert_equal true, result[:decorators][:use_regex]
  end

  def test_decorator_parser_handles_list_decorators
    parser = TavernKit::Lore::DecoratorParser.new
    result = parser.parse("@@additional_keys key1, key2, key3\n\nContent")

    assert_equal %w[key1 key2 key3], result[:decorators][:additional_keys]
  end

  def test_decorator_parser_preserves_content_without_decorators
    parser = TavernKit::Lore::DecoratorParser.new
    result = parser.parse("Just plain content\nwith multiple lines")

    assert_empty result[:decorators]
    assert_empty result[:fallback_decorators]
    assert_equal "Just plain content\nwith multiple lines", result[:content]
  end

  def test_decorator_parser_returns_empty_content_when_all_decorators
    parser = TavernKit::Lore::DecoratorParser.new
    result = parser.parse("@@depth 2\n@@role assistant\n")

    assert_equal 2, result[:decorators][:depth]
    assert_equal "assistant", result[:decorators][:role]
    assert_equal "", result[:content]  # Should be empty, not the decorator lines
  end

  # ---------------------------------------------------------------------------
  # Lore::Entry Decorator Integration Tests
  # ---------------------------------------------------------------------------

  def test_entry_parses_decorators_from_content
    entry = TavernKit::Lore::Entry.from_hash({
      "keys" => ["test"],
      "content" => "@@depth 5\n@@role user\n\nThe actual entry content",
    })

    assert_equal 5, entry.depth
    assert_equal :user, entry.role
    assert_equal "The actual entry content", entry.content
  end

  def test_entry_decorator_overrides_base_fields
    # Base field says depth=2, but @@depth 10 should override
    entry = TavernKit::Lore::Entry.from_hash({
      "keys" => ["test"],
      "content" => "@@depth 10\n\nContent",
      "depth" => 2,
    })

    assert_equal 10, entry.depth
  end

  def test_entry_use_regex_attribute
    entry = TavernKit::Lore::Entry.from_hash({
      "keys" => ["/pattern/i"],
      "content" => "Regex entry",
      "use_regex" => true,
    })

    assert entry.use_regex?
  end

  def test_entry_case_sensitive_attribute
    entry = TavernKit::Lore::Entry.from_hash({
      "keys" => ["Test"],
      "content" => "Case sensitive entry",
      "case_sensitive" => true,
    })

    assert entry.case_sensitive
  end

  def test_entry_dont_activate_decorator
    entry = TavernKit::Lore::Entry.from_hash({
      "keys" => ["test"],
      "content" => "@@dont_activate true\n\nHidden entry",
    })

    assert entry.dont_activate?
  end

  def test_entry_activate_only_after_decorator
    entry = TavernKit::Lore::Entry.from_hash({
      "keys" => ["test"],
      "content" => "@@activate_only_after 5\n\nDelayed entry",
    })

    assert_equal 5, entry.activate_only_after
  end

  def test_entry_activate_only_every_decorator
    entry = TavernKit::Lore::Entry.from_hash({
      "keys" => ["test"],
      "content" => "@@activate_only_every 3\n\nPeriodic entry",
    })

    assert_equal 3, entry.activate_only_every
  end

  def test_entry_exclude_keys_decorator
    entry = TavernKit::Lore::Entry.from_hash({
      "keys" => ["test"],
      "content" => "@@exclude_keys bad, ugly\n\nExcluding entry",
    })

    assert_equal %w[bad ugly], entry.exclude_keys
  end

  def test_entry_ignore_on_max_context_decorator
    entry = TavernKit::Lore::Entry.from_hash({
      "keys" => ["test"],
      "content" => "@@ignore_on_max_context true\n\nOptional entry",
    })

    assert entry.ignore_on_max_context?
  end

  # ---------------------------------------------------------------------------
  # Lore::Engine Regex Matching Tests
  # ---------------------------------------------------------------------------

  def test_engine_regex_matching_with_use_regex_flag
    book = TavernKit::Lore::Book.from_hash({
      "token_budget" => 1000,
      "scan_depth" => 10,
      "entries" => [
        {
          "uid" => "regex_entry",
          "keys" => ["hel+o"],
          "content" => "Regex matched",
          "use_regex" => true,
          "position" => "before_char_defs",
        },
      ],
    })

    engine = TavernKit::Lore::Engine.new
    result = engine.evaluate(book: book, scan_text: "helllo world")

    assert_equal ["regex_entry"], result.activated_entries.map(&:uid)
  end

  def test_engine_regex_matching_case_insensitive
    book = TavernKit::Lore::Book.from_hash({
      "token_budget" => 1000,
      "scan_depth" => 10,
      "entries" => [
        {
          "uid" => "regex_ci",
          "keys" => ["HELLO"],
          "content" => "Case insensitive",
          "use_regex" => true,
          "position" => "before_char_defs",
        },
      ],
    })

    engine = TavernKit::Lore::Engine.new(case_sensitive: false)
    result = engine.evaluate(book: book, scan_text: "hello world")

    assert_equal ["regex_ci"], result.activated_entries.map(&:uid)
  end

  def test_engine_js_regex_literal_keys
    # JS regex literal format /pattern/flags
    book = TavernKit::Lore::Book.from_hash({
      "token_budget" => 1000,
      "scan_depth" => 10,
      "entries" => [
        {
          "uid" => "js_regex",
          "keys" => ["/appl(e|y)/i"],
          "content" => "JS regex matched",
          "position" => "before_char_defs",
        },
      ],
    })

    engine = TavernKit::Lore::Engine.new
    result = engine.evaluate(book: book, scan_text: "I have an APPLY form")

    assert_equal ["js_regex"], result.activated_entries.map(&:uid)
  end

  def test_engine_dont_activate_decorator_prevents_keyword_activation
    book = TavernKit::Lore::Book.from_hash({
      "token_budget" => 1000,
      "scan_depth" => 10,
      "entries" => [
        {
          "uid" => "no_activate",
          "keys" => ["test"],
          "content" => "@@dont_activate true\n\nShould not activate by keyword",
          "position" => "before_char_defs",
        },
      ],
    })

    engine = TavernKit::Lore::Engine.new
    result = engine.evaluate(book: book, scan_text: "test")

    # Entry should NOT activate via keyword
    assert_empty result.activated_entries.map(&:uid)
  end

  def test_engine_activate_only_after_decorator
    book = TavernKit::Lore::Book.from_hash({
      "token_budget" => 1000,
      "scan_depth" => 10,
      "entries" => [
        {
          "uid" => "delayed",
          "keys" => ["test"],
          "content" => "@@activate_only_after 3\n\nDelayed entry",
          "position" => "before_char_defs",
        },
      ],
    })

    engine = TavernKit::Lore::Engine.new

    # With 2 messages, should not activate
    result1 = engine.evaluate(book: book, scan_text: "test", message_count: 2)
    assert_empty result1.activated_entries.map(&:uid)

    # With 5 messages, should activate
    result2 = engine.evaluate(book: book, scan_text: "test", message_count: 5)
    assert_equal ["delayed"], result2.activated_entries.map(&:uid)
  end

  def test_engine_activate_only_every_decorator
    book = TavernKit::Lore::Book.from_hash({
      "token_budget" => 1000,
      "scan_depth" => 10,
      "entries" => [
        {
          "uid" => "periodic",
          "keys" => ["test"],
          "content" => "@@activate_only_every 3\n\nPeriodic entry",
          "position" => "before_char_defs",
        },
      ],
    })

    engine = TavernKit::Lore::Engine.new

    # Message 2 - not divisible by 3
    result1 = engine.evaluate(book: book, scan_text: "test", message_count: 2)
    assert_empty result1.activated_entries.map(&:uid)

    # Message 3 - divisible by 3
    result2 = engine.evaluate(book: book, scan_text: "test", message_count: 3)
    assert_equal ["periodic"], result2.activated_entries.map(&:uid)

    # Message 6 - divisible by 3
    result3 = engine.evaluate(book: book, scan_text: "test", message_count: 6)
    assert_equal ["periodic"], result3.activated_entries.map(&:uid)
  end

  def test_engine_exclude_keys_decorator
    book = TavernKit::Lore::Book.from_hash({
      "token_budget" => 1000,
      "scan_depth" => 10,
      "entries" => [
        {
          "uid" => "excluding",
          "keys" => ["good"],
          "content" => "@@exclude_keys bad\n\nExcluding entry",
          "position" => "before_char_defs",
        },
      ],
    })

    engine = TavernKit::Lore::Engine.new

    # Should activate without exclude key
    result1 = engine.evaluate(book: book, scan_text: "good times")
    assert_equal ["excluding"], result1.activated_entries.map(&:uid)

    # Should NOT activate when exclude key is present
    result2 = engine.evaluate(book: book, scan_text: "good and bad times")
    assert_empty result2.activated_entries.map(&:uid)
  end

  # =============================================================================
  # @@position decorator tests (CCv3: personality, scenario)
  # =============================================================================

  def test_decorator_parser_position_personality
    parser = TavernKit::Lore::DecoratorParser.new
    result = parser.parse("@@position personality\n\nContent")

    assert_equal :personality, result[:decorators][:position]
    assert_equal "Content", result[:content].strip
  end

  def test_decorator_parser_position_scenario
    parser = TavernKit::Lore::DecoratorParser.new
    result = parser.parse("@@position scenario\n\nContent")

    assert_equal :scenario, result[:decorators][:position]
    assert_equal "Content", result[:content].strip
  end

  def test_entry_position_personality_from_decorator
    entry = TavernKit::Lore::Entry.from_hash({
      "uid" => "personality-entry",
      "keys" => ["test"],
      "content" => "@@position personality\n\nPersonality content",
    })

    assert_equal :personality, entry.position
    assert_equal "Personality content", entry.content.strip
  end

  def test_entry_position_scenario_from_decorator
    entry = TavernKit::Lore::Entry.from_hash({
      "uid" => "scenario-entry",
      "keys" => ["test"],
      "content" => "@@position scenario\n\nScenario content",
    })

    assert_equal :scenario, entry.position
    assert_equal "Scenario content", entry.content.strip
  end

  # =============================================================================
  # {{// comment}} macro tests (CCv3)
  # =============================================================================

  def test_comment_macro_is_removed
    engine = TavernKit::Macro::SillyTavernV2::Engine.new
    result = engine.expand("Before {{// this is a comment}} After")

    assert_equal "Before  After", result
  end

  def test_comment_macro_with_text
    engine = TavernKit::Macro::SillyTavernV2::Engine.new
    result = engine.expand("Hello {{// author note: remember to be nice}} World")

    assert_equal "Hello  World", result
  end

  def test_comment_macro_multiline
    engine = TavernKit::Macro::SillyTavernV2::Engine.new
    text = "Line 1\n{{// hidden note}}\nLine 2"
    result = engine.expand(text)

    assert_equal "Line 1\n\nLine 2", result
  end
end
