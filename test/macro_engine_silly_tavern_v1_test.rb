# frozen_string_literal: true

require "test_helper"

class MacroEngineSillyTavernV1Test < Minitest::Test
  def setup
    @expander = TavernKit::Macro::SillyTavernV1::Engine.new(unknown: :keep)
  end

  # --- Basic Macro Tests ---

  def test_expands_char_macro
    result = @expander.expand("Hello {{char}}!", { char: "Alice" })
    assert_equal "Hello Alice!", result
  end

  def test_expands_user_macro
    result = @expander.expand("Hello {{user}}!", { user: "Bob" })
    assert_equal "Hello Bob!", result
  end

  def test_expands_persona_macro
    result = @expander.expand("{{persona}}", { persona: "A brave warrior" })
    assert_equal "A brave warrior", result
  end

  def test_expands_description_macro
    result = @expander.expand("{{description}}", { description: "A wise oracle" })
    assert_equal "A wise oracle", result
  end

  def test_expands_scenario_macro
    result = @expander.expand("{{scenario}}", { scenario: "In a crystal tower" })
    assert_equal "In a crystal tower", result
  end

  def test_expands_personality_macro
    result = @expander.expand("{{personality}}", { personality: "Mysterious, kind" })
    assert_equal "Mysterious, kind", result
  end

  def test_expands_original_macro
    result = @expander.expand("Override: {{original}}", { original: "Original content" })
    assert_equal "Override: Original content", result
  end

  # --- Additional Macros (Phase 1) ---

  def test_expands_charprompt_macro
    result = @expander.expand("{{charPrompt}}", { charprompt: "You are a mystical oracle." })
    assert_equal "You are a mystical oracle.", result
  end

  def test_expands_charinstruction_macro
    result = @expander.expand("{{charInstruction}}", { charinstruction: "Speak in riddles." })
    assert_equal "Speak in riddles.", result
  end

  def test_expands_charjailbreak_macro
    result = @expander.expand("{{charJailbreak}}", { charjailbreak: "Stay in character." })
    assert_equal "Stay in character.", result
  end

  def test_charjailbreak_and_charinstruction_are_independent_keys
    # Both can be set to different values in vars (though in Builder they're aliased)
    vars = { charjailbreak: "Jailbreak text", charinstruction: "Instruction text" }
    assert_equal "Jailbreak text", @expander.expand("{{charJailbreak}}", vars)
    assert_equal "Instruction text", @expander.expand("{{charInstruction}}", vars)
  end

  def test_expands_mesexamplesraw_macro
    raw_examples = "<START>\n{{user}}: Hello\n{{char}}: Hi there"
    result = @expander.expand("{{mesExamplesRaw}}", { mesexamplesraw: raw_examples })
    assert_equal raw_examples, result
  end

  def test_expands_mesexamples_macro_with_proc
    formatted = "<START>\n{{user}}: Question?\n{{char}}: Answer."
    result = @expander.expand("{{mesExamples}}", { mesexamples: -> { formatted } })
    assert_equal formatted, result
  end

  # --- Case Insensitivity ---

  def test_macros_are_case_insensitive
    vars = {
      char: "Alice",
      charprompt: "System prompt",
      charjailbreak: "PHI text",
      mesexamplesraw: "Raw examples",
    }

    assert_equal "Alice", @expander.expand("{{CHAR}}", vars)
    assert_equal "Alice", @expander.expand("{{Char}}", vars)
    assert_equal "System prompt", @expander.expand("{{CHARPROMPT}}", vars)
    assert_equal "System prompt", @expander.expand("{{CharPrompt}}", vars)
    assert_equal "PHI text", @expander.expand("{{CHARJAILBREAK}}", vars)
    assert_equal "PHI text", @expander.expand("{{CharJailbreak}}", vars)
    assert_equal "Raw examples", @expander.expand("{{MESEXAMPLESRAW}}", vars)
    assert_equal "Raw examples", @expander.expand("{{MesExamplesRaw}}", vars)
  end

  # --- Empty/Nil Field Handling ---

  def test_empty_string_macro_returns_empty
    result = @expander.expand("X{{charprompt}}Y", { charprompt: "" })
    assert_equal "XY", result
  end

  def test_nil_macro_with_unknown_keep_preserves_macro
    result = @expander.expand("{{charprompt}}", {})
    assert_equal "{{charprompt}}", result
  end

  def test_nil_macro_with_unknown_empty_returns_empty
    expander = TavernKit::Macro::SillyTavernV1::Engine.new(unknown: :empty)
    result = expander.expand("X{{charprompt}}Y", {})
    assert_equal "XY", result
  end

  # --- Multiple Macros ---

  def test_expands_multiple_macros_in_same_text
    vars = {
      char: "Oracle",
      user: "Traveler",
      charprompt: "Be wise",
      personality: "Mysterious",
    }
    text = "{{char}} speaks to {{user}}. {{charPrompt}}. Personality: {{personality}}"
    result = @expander.expand(text, vars)
    assert_equal "Oracle speaks to Traveler. Be wise. Personality: Mysterious", result
  end

  # --- Outlet Macros (existing tests refactored) ---

  def test_outlet_macro_respects_unknown_keep_when_outlets_map_missing
    text = "Hello {{outlet::Foo}}"

    assert_equal text, @expander.expand(text, {}, allow_outlets: true)
  end

  def test_outlet_macro_respects_unknown_keep_when_outlets_map_not_a_hash
    text = "Hello {{outlet::Foo}}"

    assert_equal text, @expander.expand(text, { outlets: "nope" }, allow_outlets: true)
  end

  def test_outlet_macro_respects_unknown_empty_when_outlets_map_not_a_hash
    expander = TavernKit::Macro::SillyTavernV1::Engine.new(unknown: :empty)
    text = "Hello {{outlet::Foo}}"

    assert_equal "Hello ", expander.expand(text, { outlets: "nope" }, allow_outlets: true)
  end

  def test_outlet_macro_expands_when_outlets_map_is_a_hash
    assert_equal "Hello BAR", @expander.expand("Hello {{outlet::Foo}}", { outlets: { "Foo" => "BAR" } }, allow_outlets: true)
  end

  # --- Whitespace Handling ---

  def test_whitespace_in_macro_braces_is_trimmed
    result = @expander.expand("{{ char }}", { char: "Alice" })
    # ST evaluateMacros does not expand macros with whitespace inside braces.
    assert_equal "{{ char }}", result
  end

  def test_preserves_whitespace_around_macros
    result = @expander.expand("  {{char}}  ", { char: "Alice" })
    assert_equal "  Alice  ", result
  end

  # --- Variable Macros (ST variables system subset) ---

  def test_setvar_sets_variable_and_outputs_empty_string
    variables = TavernKit::ChatVariables.new
    result = @expander.expand("A{{setvar::x::foo}}B", { local_store: variables })

    assert_equal "AB", result
    assert_equal "foo", variables["x"]
  end

  def test_var_reads_variable_from_store
    variables = TavernKit::ChatVariables.new
    variables["x"] = "foo"
    result = @expander.expand("{{var::x}}", { local_store: variables })

    assert_equal "foo", result
  end

  def test_setvar_then_var_in_same_string_works
    variables = TavernKit::ChatVariables.new
    result = @expander.expand("{{setvar::x::foo}}{{var::x}}", { local_store: variables })

    assert_equal "foo", result
    assert_equal "foo", variables["x"]
  end

  def test_setvar_creates_ephemeral_store_when_missing
    vars = {}
    result = @expander.expand("{{setvar::x::foo}}{{var::x}}", vars)

    assert_equal "foo", result
    assert_kind_of TavernKit::ChatVariables::Base, vars[:local_store]
    assert_equal "foo", vars[:local_store]["x"]
  end

  def test_var_with_index_reads_json_object_key
    variables = TavernKit::ChatVariables.new
    variables["obj"] = '{"cool":1337,"nested":{"a":1}}'

    assert_equal "1337", @expander.expand("{{var::obj::cool}}", { local_store: variables })
    assert_equal '{"a":1}', @expander.expand("{{var::obj::nested}}", { local_store: variables })
  end

  def test_var_with_index_reads_json_array_index
    variables = TavernKit::ChatVariables.new
    variables["arr"] = "[10,20]"
    assert_equal "20", @expander.expand("{{var::arr::1}}", { local_store: variables })
  end

  def test_var_with_index_can_index_plain_strings
    variables = TavernKit::ChatVariables.new
    variables["s"] = "hello"
    assert_equal "e", @expander.expand("{{var::s::1}}", { local_store: variables })
  end

  def test_var_missing_returns_empty_string
    variables = TavernKit::ChatVariables.new
    assert_equal "", @expander.expand("{{var::missing}}", { local_store: variables })
  end

  def test_time_utc_suffix_parses_and_expands
    t = Time.new(2020, 1, 1, 12, 0, 0, "+00:00")
    expander = TavernKit::Macro::SillyTavernV1::Engine.new(unknown: :keep, clock: -> { t })

    assert_equal "1:00 PM", expander.expand("{{time_utc+1}}", {})
  end

  def test_clock_accepts_method_object
    t = Time.new(2020, 1, 1, 12, 0, 0, "+00:00")
    expander = TavernKit::Macro::SillyTavernV1::Engine.new(unknown: :keep, clock: t.method(:itself))

    assert_equal "1:00 PM", expander.expand("{{time_utc+1}}", {})
  end

  def test_timediff_parses_and_expands
    a = "2020-01-02T00:00:00Z"
    b = "2020-01-01T00:00:00Z"

    assert_equal "in a day", @expander.expand("{{timeDiff::#{a}::#{b}}}", {})
  end

  def test_invocation_syntax_can_disable_keyword_form
    t = Time.new(2020, 1, 1, 12, 0, 0, "+00:00")
    syntax = TavernKit::Macro::Packs::SillyTavern.invocation_syntax.except(:time_utc)
    expander = TavernKit::Macro::SillyTavernV1::Engine.new(unknown: :keep, clock: -> { t }, invocation_syntax: syntax)

    assert_equal "{{time_utc+1}}", expander.expand("{{time_utc+1}}", {})
  end

  def test_initializer_fails_fast_on_invalid_builtins_registry
    assert_raises(ArgumentError) do
      TavernKit::Macro::SillyTavernV1::Engine.new(builtins_registry: Object.new)
    end
  end

  def test_initializer_fails_fast_on_invalid_invocation_syntax
    assert_raises(ArgumentError) do
      TavernKit::Macro::SillyTavernV1::Engine.new(invocation_syntax: Object.new)
    end
  end
end
