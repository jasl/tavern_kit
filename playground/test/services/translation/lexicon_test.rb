# frozen_string_literal: true

require "test_helper"

class Translation::LexiconTest < ActiveSupport::TestCase
  test "glossary injects only hit entries" do
    glossary =
      ConversationSettings::I18nGlossarySettings.new(
        enabled: true,
        entries_json: [
          { src: "Eden", dst: "伊甸" },
          { src: "Nope", dst: "不会命中" },
        ].to_json
      )

    lexicon = Translation::Lexicon.new(glossary: glossary, ntl: nil)
    result = lexicon.build("Welcome to Eden.")

    assert_includes result.glossary_lines, "- Eden => 伊甸"
    refute_includes result.glossary_lines, "Nope"
    assert result.glossary_digest.present?
    assert_equal "", result.ntl_lines
    assert_equal "", result.ntl_digest
    assert_equal [], lexicon.warnings
  end

  test "ntl injects literal and regex matches" do
    ntl =
      ConversationSettings::I18nNtlSettings.new(
        enabled: true,
        entries_json: [
          { text: "{{user}}" },
          { kind: "regex", pattern: "\\b[A-Z]{2,}\\b" },
        ].to_json
      )

    lexicon = Translation::Lexicon.new(glossary: nil, ntl: ntl)
    result = lexicon.build("Hello {{user}}. SHOUTING OK.")

    assert_includes result.ntl_lines, "- {{user}}"
    assert_includes result.ntl_lines, "- SHOUTING"
    assert_includes result.ntl_lines, "- OK"
    assert result.ntl_digest.present?
    assert_equal "", result.glossary_lines
    assert_equal "", result.glossary_digest
    assert_equal [], lexicon.warnings
  end

  test "invalid JSON or regex becomes warnings, not hard failure" do
    glossary = ConversationSettings::I18nGlossarySettings.new(enabled: true, entries_json: "not json")
    ntl =
      ConversationSettings::I18nNtlSettings.new(
        enabled: true,
        entries_json: [{ kind: "regex", pattern: "(" }].to_json
      )

    lexicon = Translation::Lexicon.new(glossary: glossary, ntl: ntl)
    result = lexicon.build("Hello")

    assert_equal "", result.glossary_lines
    assert_equal "", result.ntl_lines

    joined = lexicon.warnings.join("\n")
    assert_includes joined, "glossary JSON parse error"
    assert_includes joined, "ntl regex invalid"
  end
end
