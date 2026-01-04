# frozen_string_literal: true

require "test_helper"

class TestScanBuffer < Minitest::Test
  # Test end-to-end: Entry with match_character_description matches via scan_context
  def test_entry_matches_via_scan_context
    char = TavernKit::CharacterCard.load({
      "spec" => "chara_card_v2",
      "spec_version" => "2.0",
      "data" => {
        "name" => "Alice",
        "description" => "An elf from the magical forest",
      },
    })

    user = TavernKit::User.new(name: "Bob", persona: "A human adventurer")

    preset = TavernKit::Preset.new

    # Create a book with an entry that matches on character_description
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "elf-lore",
          "keys" => "elf",
          "content" => "Elves are ancient beings with pointed ears and magical abilities.",
          "position" => 1,
          "matchCharacterDescription" => true,
        },
      ],
      "scan_depth" => 10,
    })

    # Build with a message that doesn't contain "elf"
    plan = TavernKit.build(
      character: char,
      user: user,
      preset: preset,
      lore_books: [book],
      message: "Hello, how are you today?"
    )

    # The entry should still be activated because "elf" is in character_description
    # and the entry has matchCharacterDescription enabled
    world_info_blocks = plan.blocks.select do |b|
      b.slot.to_s.include?("world_info")
    end

    contents = world_info_blocks.map(&:content).join(" ")
    assert_includes contents, "Elves are ancient beings"
  end

  # Test end-to-end: Entry with matchCharacterDepthPrompt matches via extensions.depth_prompt.prompt
  def test_entry_matches_via_character_depth_prompt
    char = TavernKit::CharacterCard.load({
      "spec" => "chara_card_v2",
      "spec_version" => "2.0",
      "data" => {
        "name" => "Alice",
        "description" => "A helpful assistant",
        "extensions" => {
          "depth_prompt" => {
            "prompt" => "Deep lore prompt here",
            "depth" => 4,
            "role" => "system",
          },
        },
      },
    })

    user = TavernKit::User.new(name: "Bob", persona: "A curious user")
    preset = TavernKit::Preset.new

    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "depth-prompt",
          "keys" => "Deep lore",
          "content" => "DEPTH_PROMPT_MATCH",
          "position" => 1,
          "matchCharacterDepthPrompt" => true,
        },
      ],
      "scan_depth" => 10,
    })

    plan = TavernKit.build(
      character: char,
      user: user,
      preset: preset,
      lore_books: [book],
      message: "Hello there"
    )

    world_info_blocks = plan.blocks.select do |b|
      b.slot.to_s.include?("world_info")
    end

    contents = world_info_blocks.map(&:content).join(" ")
    assert_includes contents, "DEPTH_PROMPT_MATCH"
  end

  # Test preset loading from ST format includes world_info_include_names
  def test_preset_from_st_json_with_world_info_include_names
    json = {
      "world_info_include_names" => true,
    }

    preset = TavernKit::Preset.from_st_preset_json(json)

    assert preset.world_info_include_names
  end

  # Test preset loading defaults world_info_include_names to true (ST default)
  def test_preset_from_st_json_defaults_world_info_include_names_to_true
    json = {}

    preset = TavernKit::Preset.from_st_preset_json(json)

    assert preset.world_info_include_names
  end

  # Test Message can be created with name
  def test_message_with_name
    msg = TavernKit::Prompt::Message.new(
      role: :user,
      content: "Hello!",
      name: "Alice"
    )

    assert_equal :user, msg.role
    assert_equal "Hello!", msg.content
    assert_equal "Alice", msg.name
  end

  # Test Message to_h includes name when present
  def test_message_to_h_with_name
    msg = TavernKit::Prompt::Message.new(
      role: :user,
      content: "Hello!",
      name: "Alice"
    )

    h = msg.to_h
    assert_equal "Alice", h[:name]
  end

  # Test Message to_h excludes name when nil or empty
  def test_message_to_h_without_name
    msg1 = TavernKit::Prompt::Message.new(role: :user, content: "Hello!")
    msg2 = TavernKit::Prompt::Message.new(role: :user, content: "Hello!", name: "")

    refute msg1.to_h.key?(:name)
    refute msg2.to_h.key?(:name)
  end
end
