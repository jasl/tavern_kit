# frozen_string_literal: true

require "test_helper"

class GroupContextTest < Minitest::Test
  def test_current_character_or_returns_fallback_when_current_character_is_nil
    group = TavernKit::GroupContext.new(members: ["Alice"], current_character: nil)

    assert_equal "Alice", group.current_character_or("Alice")
  end

  def test_notchar_falls_back_when_current_character_is_literal_nil_string
    user = TavernKit::User.new(name: "Bob", persona: nil)
    character = TavernKit::Character.create(name: "Alice", mes_example: "")

    preset = TavernKit::Preset.new(
      main_prompt: "MAIN",
      post_history_instructions: "",
      prompt_entries: [
        { "id" => "main_prompt", "pinned" => true },
        { "id" => "probe", "content" => "NC={{notChar}}", "role" => "system", "position" => "relative" },
        { "id" => "chat_history", "pinned" => true },
      ].map { |h| TavernKit::Prompt::PromptEntry.from_hash(h) },
    )

    group = TavernKit::GroupContext.new(
      members: ["Alice", "Cara"],
      muted: [],
      current_character: "nil",
    )

    plan = TavernKit.build(
      character: character,
      user: user,
      preset: preset,
      group: group,
      message: "Hi"
    )
    probe = plan.to_messages.map { |m| m[:content] }.find { |c| c&.start_with?("NC=") }

    refute_nil probe
    assert_equal "NC=Cara, Bob", probe
  end
end
