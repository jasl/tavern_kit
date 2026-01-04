# frozen_string_literal: true

require "test_helper"

class TestInstruct < Minitest::Test
  def test_default_values
    instruct = TavernKit::Instruct.new

    assert_equal false, instruct.enabled
    assert_equal "Alpaca", instruct.preset
    assert_equal "### Instruction:", instruct.input_sequence
    assert_equal "", instruct.input_suffix
    assert_equal "### Response:", instruct.output_sequence
    assert_equal "", instruct.output_suffix
    assert_equal "", instruct.system_sequence
    assert_equal "", instruct.system_suffix
    assert_equal true, instruct.wrap
    assert_equal true, instruct.macro
    assert_equal :force, instruct.names_behavior
    assert_equal true, instruct.sequences_as_stop_strings
  end

  def test_custom_values
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "<|im_start|>user",
      input_suffix: "<|im_end|>",
      output_sequence: "<|im_start|>assistant",
      output_suffix: "<|im_end|>",
      stop_sequence: "<|im_end|>",
      wrap: false,
    )

    assert_equal true, instruct.enabled
    assert_equal "<|im_start|>user", instruct.input_sequence
    assert_equal "<|im_end|>", instruct.input_suffix
    assert_equal "<|im_start|>assistant", instruct.output_sequence
    assert_equal false, instruct.wrap
  end

  def test_names_behavior_coercion
    assert_equal :none, TavernKit::Instruct::NamesBehavior.coerce("none")
    assert_equal :force, TavernKit::Instruct::NamesBehavior.coerce("force")
    assert_equal :always, TavernKit::Instruct::NamesBehavior.coerce("always")
    assert_equal :force, TavernKit::Instruct::NamesBehavior.coerce(nil)
    assert_equal :force, TavernKit::Instruct::NamesBehavior.coerce("invalid")
  end

  def test_format_chat_user_message
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### Input:",
      output_sequence: "### Output:",
      wrap: true,
    )

    result = instruct.format_chat(
      name: "Alice",
      message: "Hello!",
      is_user: true,
      user_name: "Alice",
      char_name: "Bob",
    )

    assert_includes result, "### Input:"
    assert_includes result, "Hello!"
  end

  def test_format_chat_assistant_message
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### Input:",
      output_sequence: "### Output:",
      wrap: true,
    )

    result = instruct.format_chat(
      name: "Bob",
      message: "Hi there!",
      is_user: false,
      user_name: "Alice",
      char_name: "Bob",
    )

    assert_includes result, "### Output:"
    assert_includes result, "Hi there!"
  end

  def test_format_chat_with_names_always
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### Input:",
      output_sequence: "### Output:",
      names_behavior: :always,
      wrap: true,
    )

    result = instruct.format_chat(
      name: "Alice",
      message: "Hello!",
      is_user: true,
      user_name: "Alice",
      char_name: "Bob",
    )

    assert_includes result, "Alice: Hello!"
  end

  def test_format_chat_with_names_none
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### Input:",
      output_sequence: "### Output:",
      names_behavior: :none,
      wrap: true,
    )

    result = instruct.format_chat(
      name: "Alice",
      message: "Hello!",
      is_user: true,
      user_name: "Alice",
      char_name: "Bob",
    )

    refute_includes result, "Alice:"
    assert_includes result, "Hello!"
  end

  def test_format_chat_system_message
    instruct = TavernKit::Instruct.new(
      enabled: true,
      system_sequence: "<|system|>",
      system_suffix: "</s>",
      wrap: true,
    )

    result = instruct.format_chat(
      name: "System",
      message: "You are a helpful assistant.",
      is_user: false,
      is_narrator: true,
      user_name: "Alice",
      char_name: "Bob",
    )

    assert_includes result, "<|system|>"
    assert_includes result, "You are a helpful assistant."
  end

  def test_format_chat_first_sequence_variant
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: "### Input:",
      first_input_sequence: "### First Input:",
      wrap: true,
    )

    result = instruct.format_chat(
      name: "Alice",
      message: "Hello!",
      is_user: true,
      user_name: "Alice",
      char_name: "Bob",
      force_sequence: :first,
    )

    assert_includes result, "### First Input:"
  end

  def test_format_chat_last_sequence_variant
    instruct = TavernKit::Instruct.new(
      enabled: true,
      output_sequence: "### Output:",
      last_output_sequence: "### Final Output:",
      wrap: true,
    )

    result = instruct.format_chat(
      name: "Bob",
      message: "Goodbye!",
      is_user: false,
      user_name: "Alice",
      char_name: "Bob",
      force_sequence: :last,
    )

    assert_includes result, "### Final Output:"
  end

  def test_stopping_sequences_when_disabled
    instruct = TavernKit::Instruct.new(enabled: false)

    result = instruct.stopping_sequences

    assert_empty result
  end

  def test_stopping_sequences_when_enabled
    instruct = TavernKit::Instruct.new(
      enabled: true,
      stop_sequence: "<|stop|>",
      input_sequence: "### Input:",
      output_sequence: "### Output:",
      sequences_as_stop_strings: true,
      wrap: true,
    )

    result = instruct.stopping_sequences

    assert_includes result, "\n<|stop|>"
    assert_includes result, "\n### Input:"
    assert_includes result, "\n### Output:"
  end

  def test_stopping_sequences_without_wrap
    instruct = TavernKit::Instruct.new(
      enabled: true,
      stop_sequence: "<|stop|>",
      wrap: false,
    )

    result = instruct.stopping_sequences

    assert_includes result, "<|stop|>"
    refute_includes result, "\n<|stop|>"
  end

  def test_format_story_string
    instruct = TavernKit::Instruct.new(
      enabled: true,
      story_string_prefix: "### System Context:",
      story_string_suffix: "### End Context",
      wrap: true,
    )

    result = instruct.format_story_string("This is the story.")

    assert_includes result, "### System Context:"
    assert_includes result, "This is the story."
    assert_includes result, "### End Context"
  end

  def test_format_story_string_empty
    instruct = TavernKit::Instruct.new(enabled: true)

    result = instruct.format_story_string("")

    assert_equal "", result
  end

  def test_format_story_string_in_chat_position
    instruct = TavernKit::Instruct.new(
      enabled: true,
      story_string_prefix: "### System:",
      story_string_suffix: "### End",
      wrap: true,
    )

    result = instruct.format_story_string("Story content", in_chat_position: true)

    # In-chat position should not add prefix/suffix
    refute_includes result, "### System:"
    refute_includes result, "### End"
    assert_includes result, "Story content"
  end

  def test_with_creates_new_instance
    instruct = TavernKit::Instruct.new(enabled: false)
    new_instruct = instruct.with(enabled: true, stop_sequence: "<|stop|>")

    assert_equal false, instruct.enabled
    assert_equal true, new_instruct.enabled
    assert_equal "<|stop|>", new_instruct.stop_sequence
  end

  def test_to_h
    instruct = TavernKit::Instruct.new(
      enabled: true,
      input_sequence: ">>> User:",
    )

    hash = instruct.to_h

    assert_equal true, hash[:enabled]
    assert_equal ">>> User:", hash[:input_sequence]
    assert_kind_of Hash, hash
  end

  def test_from_st_json
    json = {
      "enabled" => true,
      "input_sequence" => "[INST]",
      "output_sequence" => "[/INST]",
      "wrap" => false,
      "names_behavior" => "always",
    }

    instruct = TavernKit::Instruct.from_st_json(json)

    assert_equal true, instruct.enabled
    assert_equal "[INST]", instruct.input_sequence
    assert_equal "[/INST]", instruct.output_sequence
    assert_equal false, instruct.wrap
    assert_equal :always, instruct.names_behavior
  end

  def test_from_st_json_with_legacy_names_migration
    json = {
      "enabled" => true,
      "names" => true,
    }

    instruct = TavernKit::Instruct.from_st_json(json)

    assert_equal :always, instruct.names_behavior
  end

  def test_from_st_json_with_separator_sequence_migration
    json = {
      "enabled" => true,
      "separator_sequence" => "</s>",
    }

    instruct = TavernKit::Instruct.from_st_json(json)

    assert_equal "</s>", instruct.output_suffix
  end

  def test_from_st_json_nil
    instruct = TavernKit::Instruct.from_st_json(nil)

    assert_equal false, instruct.enabled
  end
end
