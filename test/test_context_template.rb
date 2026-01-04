# frozen_string_literal: true

require "test_helper"

class TestContextTemplate < Minitest::Test
  def test_default_values
    context = TavernKit::ContextTemplate.new

    assert_equal "Default", context.preset
    assert_includes context.story_string, "{{#if system}}"
    assert_equal "***", context.chat_start
    assert_equal "***", context.example_separator
    assert_equal true, context.use_stop_strings
    assert_equal true, context.names_as_stop_strings
    assert_equal :in_prompt, context.story_string_position
    assert_equal :system, context.story_string_role
    assert_equal 1, context.story_string_depth
  end

  def test_custom_values
    context = TavernKit::ContextTemplate.new(
      preset: "ChatML",
      story_string: "{{description}}",
      chat_start: "[Start]",
      example_separator: "---",
      story_string_position: :in_chat,
      story_string_depth: 3,
    )

    assert_equal "ChatML", context.preset
    assert_equal "{{description}}", context.story_string
    assert_equal "[Start]", context.chat_start
    assert_equal "---", context.example_separator
    assert_equal :in_chat, context.story_string_position
    assert_equal 3, context.story_string_depth
  end

  def test_position_coercion
    assert_equal :in_prompt, TavernKit::ContextTemplate::Position.coerce(0)
    assert_equal :in_chat, TavernKit::ContextTemplate::Position.coerce(1)
    assert_equal :before_prompt, TavernKit::ContextTemplate::Position.coerce(2)
    assert_equal :in_prompt, TavernKit::ContextTemplate::Position.coerce("0")
    assert_equal :in_prompt, TavernKit::ContextTemplate::Position.coerce(nil)
    assert_equal :in_chat, TavernKit::ContextTemplate::Position.coerce("in_chat")
    assert_equal :in_prompt, TavernKit::ContextTemplate::Position.coerce("invalid")
  end

  def test_role_coercion
    assert_equal :system, TavernKit::ContextTemplate::Role.coerce(0)
    assert_equal :user, TavernKit::ContextTemplate::Role.coerce(1)
    assert_equal :assistant, TavernKit::ContextTemplate::Role.coerce(2)
    assert_equal :system, TavernKit::ContextTemplate::Role.coerce(nil)
    assert_equal :assistant, TavernKit::ContextTemplate::Role.coerce("assistant")
  end

  def test_render_simple_template
    context = TavernKit::ContextTemplate.new(
      story_string: "{{description}}\n{{personality}}",
    )

    result = context.render(
      description: "A brave knight",
      personality: "Courageous and noble",
    )

    assert_includes result, "A brave knight"
    assert_includes result, "Courageous and noble"
  end

  def test_render_with_conditional_blocks
    context = TavernKit::ContextTemplate.new(
      story_string: "{{#if system}}System: {{system}}\n{{/if}}Description: {{description}}",
    )

    # With system provided
    result_with_system = context.render(
      system: "You are helpful",
      description: "A character",
    )
    assert_includes result_with_system, "System: You are helpful"
    assert_includes result_with_system, "Description: A character"

    # Without system
    result_without_system = context.render(
      description: "A character",
    )
    refute_includes result_without_system, "System:"
    assert_includes result_without_system, "Description: A character"
  end

  def test_render_with_unless_blocks
    context = TavernKit::ContextTemplate.new(
      story_string: "{{#unless persona}}No persona provided{{/unless}}{{#if persona}}{{persona}}{{/if}}",
    )

    # Without persona
    result_without = context.render({})
    assert_includes result_without, "No persona provided"

    # With persona
    result_with = context.render(persona: "I am the user")
    refute_includes result_with, "No persona provided"
    assert_includes result_with, "I am the user"
  end

  def test_render_ensures_trailing_newline
    context = TavernKit::ContextTemplate.new(
      story_string: "Test content",
    )

    result = context.render({})

    assert result.end_with?("\n")
  end

  def test_render_empty_returns_empty
    context = TavernKit::ContextTemplate.new(
      story_string: "",
    )

    result = context.render({})

    assert_equal "", result
  end

  def test_render_with_char_and_user_macros
    context = TavernKit::ContextTemplate.new(
      story_string: "{{char}}: {{description}}\n{{user}}: {{persona}}",
    )

    result = context.render(
      char: "Alice",
      user: "Bob",
      description: "A curious AI",
      persona: "A friendly human",
    )

    assert_includes result, "Alice: A curious AI"
    assert_includes result, "Bob: A friendly human"
  end

  def test_render_nested_conditionals
    context = TavernKit::ContextTemplate.new(
      story_string: "{{#if description}}Desc: {{description}}\n{{#if personality}}Personality: {{personality}}\n{{/if}}{{/if}}",
    )

    result = context.render(
      description: "A knight",
      personality: "Brave",
    )

    assert_includes result, "Desc: A knight"
    assert_includes result, "Personality: Brave"
  end

  def test_stopping_strings
    context = TavernKit::ContextTemplate.new(
      names_as_stop_strings: true,
    )

    result = context.stopping_strings(user_name: "Alice", char_name: "Bob")

    assert_includes result, "\nBob:"
    assert_includes result, "\nAlice:"
  end

  def test_stopping_strings_disabled
    context = TavernKit::ContextTemplate.new(
      names_as_stop_strings: false,
    )

    result = context.stopping_strings(user_name: "Alice", char_name: "Bob")

    assert_empty result
  end

  def test_with_creates_new_instance
    context = TavernKit::ContextTemplate.new(
      chat_start: "[Start]",
    )
    new_context = context.with(chat_start: "[Begin]", example_separator: "---")

    assert_equal "[Start]", context.chat_start
    assert_equal "[Begin]", new_context.chat_start
    assert_equal "---", new_context.example_separator
  end

  def test_to_h
    context = TavernKit::ContextTemplate.new(
      preset: "Custom",
      chat_start: "[Go]",
    )

    hash = context.to_h

    assert_equal "Custom", hash[:preset]
    assert_equal "[Go]", hash[:chat_start]
    assert_kind_of Hash, hash
  end

  def test_from_st_json
    json = {
      "preset" => "Llama",
      "story_string" => "{{description}}",
      "chat_start" => "[Chat]",
      "example_separator" => "---",
      "story_string_position" => 1,
      "story_string_depth" => 2,
    }

    context = TavernKit::ContextTemplate.from_st_json(json)

    assert_equal "Llama", context.preset
    assert_equal "{{description}}", context.story_string
    assert_equal "[Chat]", context.chat_start
    assert_equal "---", context.example_separator
    assert_equal :in_chat, context.story_string_position
    assert_equal 2, context.story_string_depth
  end

  def test_from_st_json_nil
    context = TavernKit::ContextTemplate.from_st_json(nil)

    assert_equal "Default", context.preset
  end

  def test_default_story_string_template
    context = TavernKit::ContextTemplate.new

    result = context.render(
      system: "Be helpful",
      description: "A friendly AI",
      personality: "Kind",
      scenario: "A chat",
      persona: "A user",
      char: "Assistant",
    )

    assert_includes result, "Be helpful"
    assert_includes result, "A friendly AI"
    assert_includes result, "Assistant's personality: Kind"
    assert_includes result, "Scenario: A chat"
    assert_includes result, "A user"
  end
end
