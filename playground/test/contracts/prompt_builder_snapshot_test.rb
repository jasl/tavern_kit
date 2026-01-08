# frozen_string_literal: true

require "test_helper"

class PromptBuilderSnapshotTest < ActiveSupport::TestCase
  SNAPSHOT_DIR = Rails.root.join("test", "fixtures", "files", "snapshots").freeze

  def assert_snapshot(name, actual)
    path = SNAPSHOT_DIR.join("#{name}.yml")

    if ENV["UPDATE_SNAPSHOTS"] == "1"
      path.dirname.mkpath
      path.write(YAML.dump(actual))
      assert true
      return
    end

    unless path.exist?
      flunk <<~MSG
        Missing snapshot: #{path}
        Re-run with UPDATE_SNAPSHOTS=1 to generate it.
      MSG
    end

    expected = YAML.safe_load(path.read)
    assert_equal expected, actual
  end

  def normalize_messages(messages)
    messages.map do |m|
      {
        "role" => m.fetch(:role),
        "content" => normalize_text(m.fetch(:content)),
      }
    end
  end

  def normalize_text(text)
    text.to_s.gsub("\r\n", "\n").gsub("\r", "\n")
  end

  def snapshot_preset
    TavernKit::Preset.new(
      main_prompt: "SNAPSHOT_MAIN_PROMPT",
      new_chat_prompt: "SNAPSHOT_NEW_CHAT_PROMPT",
      new_group_chat_prompt: "SNAPSHOT_NEW_GROUP_CHAT_PROMPT",
      group_nudge_prompt: "SNAPSHOT_GROUP_NUDGE_PROMPT",
      post_history_instructions: "SNAPSHOT_POST_HISTORY_INSTRUCTIONS",
      authors_note: "SNAPSHOT_AUTHORS_NOTE",
      squash_system_messages: false,
      context_window_tokens: 2048,
      reserved_response_tokens: 128
    )
  end

  test "prompt_builder openai messages (solo swap)" do
    conversation = conversations(:general_main)
    speaker = space_memberships(:character_in_general)

    builder =
      PromptBuilder.new(
        conversation,
        speaker: speaker,
        user_message: "Hello from snapshot",
        preset: snapshot_preset,
        card_handling_mode: "swap"
      )

    messages = builder.to_messages
    assert_kind_of Array, messages

    assert_snapshot("prompt_builder/solo_swap_openai", normalize_messages(messages))
  end

  test "prompt_builder openai messages (group append_disabled join)" do
    conversation = conversations(:ai_chat_main)
    speaker = space_memberships(:v2_character_in_ai_chat)

    conversation.space.update!(
      prompt_settings: {
        "join_prefix" => "<<{{char}}:<FIELDNAME>>",
        "join_suffix" => "<</{{char}}:<FIELDNAME>>",
        "scenario_override" => "OVERRIDE SCENARIO",
      }
    )

    builder =
      PromptBuilder.new(
        conversation,
        speaker: speaker,
        user_message: "Hello group snapshot",
        preset: snapshot_preset,
        card_handling_mode: "append_disabled"
      )

    messages = builder.to_messages
    assert_kind_of Array, messages

    assert_snapshot("prompt_builder/group_append_disabled_openai", normalize_messages(messages))
  end
end
