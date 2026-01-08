# frozen_string_literal: true

require "test_helper"

class PresetWithTest < Minitest::Test
  def test_with_returns_a_copy_with_overrides
    preset = TavernKit::Preset.new(main_prompt: "Hello", context_window_tokens: 123)
    next_preset = preset.with(reserved_response_tokens: 45)

    assert_equal "Hello", preset.main_prompt
    assert_equal 123, preset.context_window_tokens
    assert_equal 0, preset.reserved_response_tokens

    assert_equal "Hello", next_preset.main_prompt
    assert_equal 123, next_preset.context_window_tokens
    assert_equal 45, next_preset.reserved_response_tokens
  end

  def test_default_utility_prompts_match_sillytavern_defaults
    preset = TavernKit::Preset.new

    assert_equal TavernKit::Preset::DEFAULT_NEW_CHAT_PROMPT, preset.new_chat_prompt
    assert_equal TavernKit::Preset::DEFAULT_NEW_GROUP_CHAT_PROMPT, preset.new_group_chat_prompt
    assert_equal TavernKit::Preset::DEFAULT_NEW_EXAMPLE_CHAT_PROMPT, preset.new_example_chat
    assert_equal TavernKit::Preset::DEFAULT_GROUP_NUDGE_PROMPT, preset.group_nudge_prompt
    assert_equal TavernKit::Preset::DEFAULT_CONTINUE_NUDGE_PROMPT, preset.continue_nudge_prompt
  end
end
