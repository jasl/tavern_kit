# frozen_string_literal: true

require "test_helper"

class TestTextDialect < Minitest::Test
  def test_simple_conversion
    messages = [
      { role: "system", content: "You are helpful" },
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi there" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(messages)

    assert_kind_of Hash, result
    assert result[:prompt].include?("System: You are helpful")
    assert result[:prompt].include?("user: Hello")
    assert result[:prompt].include?("assistant: Hi there")
    assert result[:prompt].end_with?("assistant:")
  end

  def test_with_custom_names
    messages = [
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      names: { user_name: "Alice", char_name: "Bob" },
    )

    assert result[:prompt].include?("Alice: Hello")
    assert result[:prompt].include?("Bob: Hi")
    assert result[:prompt].end_with?("Bob:")
  end

  def test_stop_sequences_without_instruct
    messages = [
      { role: "user", content: "Test" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      names: { user_name: "Alice", char_name: "Bob" },
    )

    assert_includes result[:stop_sequences], "\nAlice:"
    assert_includes result[:stop_sequences], "\nBob:"
  end

  def test_with_instruct_mode
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### User:",
      output_sequence: "### Assistant:",
      wrap: true,
    )

    messages = [
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi there" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      instruct: instruct,
      names: { user_name: "Alice", char_name: "Bob" },
    )

    assert_includes result[:prompt], "### User:"
    assert_includes result[:prompt], "Hello"
    assert_includes result[:prompt], "### Assistant:"
    assert_includes result[:prompt], "Hi there"
  end

  def test_instruct_stop_sequences
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### User:",
      output_sequence: "### Assistant:",
      stop_sequence: "<|stop|>",
      sequences_as_stop_strings: true,
      wrap: true,
    )

    messages = [
      { role: "user", content: "Hello" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      instruct: instruct,
    )

    assert_includes result[:stop_sequences], "\n<|stop|>"
    assert_includes result[:stop_sequences], "\n### User:"
    assert_includes result[:stop_sequences], "\n### Assistant:"
  end

  def test_instruct_with_names_always
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "[User]",
      output_sequence: "[Assistant]",
      names_behavior: :always,
      wrap: true,
    )

    messages = [
      { role: "user", content: "Hello" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      instruct: instruct,
      names: { user_name: "Alice", char_name: "Bob" },
    )

    assert_includes result[:prompt], "Alice: Hello"
  end

  def test_instruct_without_wrap
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "[U]",
      output_sequence: "[A]",
      wrap: false,
    )

    messages = [
      { role: "user", content: "Hello" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      instruct: instruct,
    )

    # Without wrap, sequences should not have leading newlines in stop sequences
    assert_includes result[:stop_sequences], "[U]"
    refute_includes result[:stop_sequences], "\n[U]"
  end

  def test_with_context_template_stop_strings
    context = TavernKit::ContextTemplate.new(
      names_as_stop_strings: true,
    )

    messages = [
      { role: "user", content: "Hello" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      context_template: context,
      names: { user_name: "Alice", char_name: "Bob" },
    )

    assert_includes result[:stop_sequences], "\nBob:"
    assert_includes result[:stop_sequences], "\nAlice:"
  end

  def test_without_assistant_suffix
    messages = [
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      include_assistant_suffix: false,
    )

    refute result[:prompt].end_with?("assistant:")
    assert result[:prompt].end_with?("Hi")
  end

  def test_with_assistant_prefill
    messages = [
      { role: "user", content: "Hello" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      assistant_prefill: "Sure, let me",
      names: { char_name: "Bot" },
    )

    assert result[:prompt].include?("Bot: Sure, let me")
  end

  def test_instruct_with_assistant_prefill
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### User:",
      output_sequence: "### Assistant:",
      wrap: true,
    )

    messages = [
      { role: "user", content: "Hello" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      instruct: instruct,
      assistant_prefill: "Of course",
    )

    assert result[:prompt].include?("### Assistant:")
    assert result[:prompt].include?("Of course")
  end

  def test_system_message_with_name
    messages = [
      { role: "system", name: "Narrator", content: "The story begins" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(messages)

    assert result[:prompt].include?("Narrator: The story begins")
  end

  def test_instruct_system_message
    instruct = TavernKit::Instruct.new(
      enabled: true,
      system_sequence: "### System:",
      system_suffix: "</s>",
      input_sequence: "### User:",
      output_sequence: "### Assistant:",
      wrap: true,
    )

    messages = [
      { role: "system", content: "Be helpful" },
      { role: "user", content: "Hello" },
    ]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      instruct: instruct,
    )

    assert_includes result[:prompt], "### System:"
    assert_includes result[:prompt], "Be helpful"
  end

  def test_stop_sequences_are_unique
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### User:",
      output_sequence: "### User:", # Same as input for this test
      stop_sequence: "### User:",   # Same again
      sequences_as_stop_strings: true,
      wrap: true,
    )

    messages = [{ role: "user", content: "Test" }]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      instruct: instruct,
    )

    # Should not have duplicates
    assert_equal result[:stop_sequences].uniq, result[:stop_sequences]
  end

  def test_empty_stop_sequences_filtered
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### User:",
      output_sequence: "",  # Empty
      stop_sequence: "",    # Empty
      sequences_as_stop_strings: true,
      wrap: true,
    )

    messages = [{ role: "user", content: "Test" }]

    result = TavernKit::Prompt::Dialects::Text.convert(
      messages,
      instruct: instruct,
    )

    # Should not contain empty strings
    refute result[:stop_sequences].any?(&:empty?)
  end
end
