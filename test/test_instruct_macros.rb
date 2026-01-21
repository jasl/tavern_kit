# frozen_string_literal: true

require "test_helper"

class TestInstructMacros < Minitest::Test
  def setup
    @instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### User:",
      output_sequence: "### Assistant:",
      system_sequence: "### System:",
      input_suffix: "</user>",
      output_suffix: "</assistant>",
      system_suffix: "</system>",
      first_input_sequence: "### First User:",
      last_output_sequence: "### Final Assistant:",
      story_string_prefix: "[Context Start]",
      story_string_suffix: "[Context End]",
    )

    @context_template = TavernKit::ContextTemplate.new(
      chat_start: "[Chat Begins]",
      example_separator: "---",
    )

    @preset = TavernKit::Preset.new(
      main_prompt: "You are a helpful assistant.",
      instruct: @instruct,
      context_template: @context_template,
    )

    @registry = TavernKit::Macro::Packs::SillyTavern.builder_registry
  end

  def test_instruct_input_macro
    ctx = build_context
    result = evaluate_macro("instructinput", ctx)
    assert_equal "### User:", result
  end

  def test_instruct_user_prefix_alias
    ctx = build_context
    result = evaluate_macro("instructuserprefix", ctx)
    assert_equal "### User:", result
  end

  def test_instruct_output_macro
    ctx = build_context
    result = evaluate_macro("instructoutput", ctx)
    assert_equal "### Assistant:", result
  end

  def test_instruct_assistant_prefix_alias
    ctx = build_context
    result = evaluate_macro("instructassistantprefix", ctx)
    assert_equal "### Assistant:", result
  end

  def test_instruct_system_macro
    ctx = build_context
    result = evaluate_macro("instructsystem", ctx)
    assert_equal "### System:", result
  end

  def test_instruct_input_suffix_macro
    ctx = build_context
    result = evaluate_macro("instructinputsuffix", ctx)
    assert_equal "</user>", result
  end

  def test_instruct_output_suffix_macro
    ctx = build_context
    result = evaluate_macro("instructoutputsuffix", ctx)
    assert_equal "</assistant>", result
  end

  def test_instruct_system_suffix_macro
    ctx = build_context
    result = evaluate_macro("instructsystemsuffix", ctx)
    assert_equal "</system>", result
  end

  def test_instruct_first_input_macro
    ctx = build_context
    result = evaluate_macro("instructfirstinput", ctx)
    assert_equal "### First User:", result
  end

  def test_instruct_last_output_macro
    ctx = build_context
    result = evaluate_macro("instructlastoutput", ctx)
    assert_equal "### Final Assistant:", result
  end

  def test_instruct_first_output_fallback
    ctx = build_context
    result = evaluate_macro("instructfirstoutput", ctx)
    # Should fall back to output_sequence ("### Assistant:") since first_output_sequence is empty
    assert_equal "### Assistant:", result
  end

  def test_instruct_story_string_prefix_macro
    ctx = build_context
    result = evaluate_macro("instructstorystringprefix", ctx)
    assert_equal "[Context Start]", result
  end

  def test_instruct_story_string_suffix_macro
    ctx = build_context
    result = evaluate_macro("instructstorystringsuffix", ctx)
    assert_equal "[Context End]", result
  end

  def test_chat_separator_macro
    ctx = build_context
    result = evaluate_macro("chatseparator", ctx)
    assert_equal "---", result
  end

  def test_chat_start_macro
    ctx = build_context
    result = evaluate_macro("chatstart", ctx)
    assert_equal "[Chat Begins]", result
  end

  def test_system_prompt_macro
    ctx = build_context
    result = evaluate_macro("systemprompt", ctx)
    assert_equal "You are a helpful assistant.", result
  end

  def test_system_prompt_prefers_character_override
    card = TavernKit::Character.create(
      name: "TestChar",
      system_prompt: "Character-specific system prompt",
    )

    preset_with_prefer = TavernKit::Preset.new(
      main_prompt: "Global prompt",
      prefer_char_prompt: true,
    )

    ctx = build_context(card: card, preset: preset_with_prefer)

    result = evaluate_macro("systemprompt", ctx)
    assert_equal "Character-specific system prompt", result
  end

  def test_global_system_prompt_macro
    card = TavernKit::Character.create(
      name: "TestChar",
      system_prompt: "Character-specific prompt",
    )

    preset = TavernKit::Preset.new(
      main_prompt: "Global system prompt",
      prefer_char_prompt: true,
    )

    ctx = build_context(card: card, preset: preset)

    result = evaluate_macro("globalsystemprompt", ctx)
    assert_equal "Global system prompt", result
  end

  def test_macros_return_empty_without_preset
    ctx = build_context(preset: nil)

    assert_equal "", evaluate_macro("instructinput", ctx)
    assert_equal "", evaluate_macro("chatstart", ctx)
  end

  NOT_PROVIDED = Object.new.freeze
  private_constant :NOT_PROVIDED

  private

  def build_context(card: nil, user: nil, preset: NOT_PROVIDED)
    p = preset.equal?(NOT_PROVIDED) ? @preset : preset
    TavernKit::MacroContext.new(
      card: card || TavernKit::Character.create(name: "TestChar"),
      user: user || TavernKit::User.new(name: "TestUser"),
      history: TavernKit::ChatHistory::InMemory.new,
      local_store: TavernKit::ChatVariables::InMemory.new,
      preset: p,
    )
  end

  # Evaluate a macro by name with the given context.
  # The registry stores Procs that take a context and optional invocation.
  def evaluate_macro(name, ctx)
    value = @registry.get(name)
    return "" if value.nil?

    if value.respond_to?(:execute)
      value.execute(ctx)
    else
      value.to_s
    end
  end
end
