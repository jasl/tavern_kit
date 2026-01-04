# frozen_string_literal: true

require "test_helper"

class TestCharacter < Minitest::Test
  def test_create_minimal_character
    character = TavernKit::Character.create(name: "Test")

    assert_equal "Test", character.data.name
    assert_equal "Test", character.name
    assert_nil character.source_version
    assert_nil character.raw
  end

  def test_create_with_all_fields
    character = TavernKit::Character.create(
      name: "Nova",
      description: "A starship captain",
      personality: "Brave, curious",
      scenario: "Space adventure",
      first_mes: "Welcome aboard!",
      mes_example: "<START>\n{{user}}: Hello\n{{char}}: Greetings!",
      creator_notes: "Test character",
      system_prompt: "You are Nova",
      post_history_instructions: "Stay in character",
      alternate_greetings: ["Hi there!", "Greetings!"],
      character_book: { "name" => "Lore", "entries" => [] },
      tags: ["sci-fi", "space"],
      creator: "Test Author",
      character_version: "1.0.0",
      extensions: { "custom" => "data" },
      group_only_greetings: ["Team, assemble!"],
      assets: [{ "type" => "icon", "uri" => "ccdefault:icon.png" }],
      nickname: "Captain Nova",
      creator_notes_multilingual: { "en" => "Test", "ja" => "テスト" },
      source: ["https://example.com"],
      creation_date: 1703462400,
      modification_date: 1703548800
    )

    assert_equal "Nova", character.data.name
    assert_equal "A starship captain", character.data.description
    assert_equal "Brave, curious", character.data.personality
    assert_equal "Space adventure", character.data.scenario
    assert_equal "Welcome aboard!", character.data.first_mes
    assert_equal ["Hi there!", "Greetings!"], character.data.alternate_greetings
    assert_equal ["sci-fi", "space"], character.data.tags
    assert_equal "Test Author", character.data.creator
    assert_equal "1.0.0", character.data.character_version
    assert_equal({ "custom" => "data" }, character.data.extensions)
    assert_equal ["Team, assemble!"], character.data.group_only_greetings
    assert_equal "Captain Nova", character.data.nickname
    assert_equal 1703462400, character.data.creation_date
    assert_equal 1703548800, character.data.modification_date
  end

  def test_v2_predicate
    data = build_minimal_data
    character = TavernKit::Character.new(data: data, source_version: :v2)

    assert character.v2?
    refute character.v3?
  end

  def test_v3_predicate
    data = build_minimal_data
    character = TavernKit::Character.new(data: data, source_version: :v3)

    assert character.v3?
    refute character.v2?
  end

  def test_no_source_version
    data = build_minimal_data
    character = TavernKit::Character.new(data: data)

    refute character.v2?
    refute character.v3?
    assert_nil character.source_version
  end

  private

  def build_minimal_data
    TavernKit::Character::Data.new(
      name: "Test",
      description: nil,
      personality: nil,
      scenario: nil,
      first_mes: nil,
      mes_example: nil,
      creator_notes: "",
      system_prompt: "",
      post_history_instructions: "",
      alternate_greetings: [],
      character_book: nil,
      tags: [],
      creator: "",
      character_version: "",
      extensions: {},
      group_only_greetings: [],
      assets: nil,
      nickname: nil,
      creator_notes_multilingual: nil,
      source: nil,
      creation_date: nil,
      modification_date: nil
    )
  end
end
