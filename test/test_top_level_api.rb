# frozen_string_literal: true

require "test_helper"

class TestTopLevelAPI < Minitest::Test
  def setup
    @fixture_path = File.expand_path("fixtures/seraphina.v2.json", __dir__)
    @character_hash = {
      "spec" => "chara_card_v2",
      "spec_version" => "2.0",
      "data" => {
        "name" => "TestBot",
        "description" => "A test character.",
        "personality" => "Friendly.",
        "scenario" => "Testing scenario.",
        "first_mes" => "Hello!",
        "mes_example" => "",
        "system_prompt" => "",
        "post_history_instructions" => "",
        "creator_notes" => "",
        "alternate_greetings" => [],
        "tags" => [],
        "creator" => "",
        "character_version" => "",
        "extensions" => {},
      },
    }
  end

  # --- TavernKit.load_character ---

  def test_load_character_from_file
    character = TavernKit.load_character(@fixture_path)

    assert_instance_of TavernKit::Character, character
    assert_equal "Seraphina", character.name
  end

  def test_load_character_from_hash
    character = TavernKit.load_character(@character_hash)

    assert_instance_of TavernKit::Character, character
    assert_equal "TestBot", character.name
  end

  # --- TavernKit.load_preset ---

  def test_load_preset_from_simple_hash
    preset = TavernKit.load_preset(
      main_prompt: "You are {{char}}.",
      prefer_char_prompt: false
    )

    assert_instance_of TavernKit::Preset, preset
    assert_equal "You are {{char}}.", preset.main_prompt
    assert_equal false, preset.prefer_char_prompt
  end

  def test_load_preset_from_string_keyed_hash
    preset = TavernKit.load_preset(
      "main_prompt" => "Custom prompt.",
      "post_history_instructions" => "Stay in character."
    )

    assert_instance_of TavernKit::Preset, preset
    assert_equal "Custom prompt.", preset.main_prompt
    assert_equal "Stay in character.", preset.post_history_instructions
  end

  def test_load_preset_detects_st_format
    st_preset_hash = {
      "prompts" => [
        { "identifier" => "main", "role" => 0, "content" => "ST Main" },
        { "identifier" => "jailbreak", "role" => 0, "content" => "ST PHI" },
      ],
      "prompt_order" => [
        { "identifier" => "main", "enabled" => true },
      ],
    }

    preset = TavernKit.load_preset(st_preset_hash)

    assert_instance_of TavernKit::Preset, preset
    assert_equal "ST Main", preset.main_prompt
    assert_equal "ST PHI", preset.post_history_instructions
  end

  def test_load_preset_detects_st_format_with_symbol_keys
    st_preset_hash = {
      prompts: [
        { identifier: "main", role: 0, content: "ST Main" },
        { identifier: "jailbreak", role: 0, content: "ST PHI" },
      ],
      prompt_order: [
        { identifier: "main", enabled: true },
      ],
    }

    preset = TavernKit.load_preset(st_preset_hash)

    assert_instance_of TavernKit::Preset, preset
    assert_equal "ST Main", preset.main_prompt
    assert_equal "ST PHI", preset.post_history_instructions
    refute_nil preset.prompt_entries
    assert preset.prompt_entries.any? { |e| e.id == "main_prompt" }
  end

  def test_load_preset_returns_default_for_invalid_input
    preset = TavernKit.load_preset(123)
    assert_instance_of TavernKit::Preset, preset
  end

  # --- TavernKit.build (DSL-based Pipeline API) ---

  def test_build_returns_prompt_plan
    plan = TavernKit.build(
      character: @character_hash,
      user: "TestUser",
      preset: { main_prompt: "Test prompt." },
      message: "Hello!"
    )

    assert_instance_of TavernKit::Prompt::Plan, plan
    messages = plan.to_messages
    assert messages.is_a?(Array)
    assert messages.any? { |m| m[:content].include?("Hello!") }
    system_content = messages.select { |m| m[:role] == "system" }.map { |m| m[:content] }.join
    assert system_content.include?("Test prompt.")
  end

  def test_build_with_block_style
    card = TavernKit.load_character(@character_hash)
    my_user = TavernKit::User.new(name: "TestUser", persona: "A tester")
    my_preset = TavernKit::Preset.new(main_prompt: "Test prompt.")

    plan = TavernKit.build do
      character card
      user my_user
      preset my_preset
      message "Hello!"
    end

    assert_instance_of TavernKit::Prompt::Plan, plan
    messages = plan.to_messages
    assert messages.is_a?(Array)
    assert messages.any? { |m| m[:content].include?("Hello!") }
  end

  def test_build_coerces_user_hash
    plan = TavernKit.build(
      character: @character_hash,
      user: { name: "Alice", persona: "A traveler" },
      message: "Hello!"
    )

    assert_instance_of TavernKit::Prompt::Plan, plan
    messages = plan.to_messages
    system_content = messages.select { |m| m[:role] == "system" }.map { |m| m[:content] }.join
    assert system_content.include?("Alice") || system_content.include?("traveler")
  end

  def test_build_with_history
    character = TavernKit.load_character(@character_hash)
    user = TavernKit::User.new(name: "TestUser")
    preset = TavernKit::Preset.new(main_prompt: "Test.")

    history = TavernKit::ChatHistory.wrap([
      TavernKit::Prompt::Message.new(role: :user, content: "First message"),
      TavernKit::Prompt::Message.new(role: :assistant, content: "First response"),
    ])

    plan = TavernKit.build(
      character: character,
      user: user,
      preset: preset,
      history: history,
      message: "Second message"
    )

    messages = plan.to_messages
    contents = messages.map { |m| m[:content] }

    assert contents.any? { |c| c.include?("First message") }
    assert contents.any? { |c| c.include?("First response") }
    assert contents.any? { |c| c.include?("Second message") }
  end

  def test_build_requires_character
    assert_raises(ArgumentError) do
      TavernKit.build(user: "TestUser", message: "Hello!")
    end
  end

  def test_build_requires_user
    assert_raises(ArgumentError) do
      TavernKit.build(character: @character_hash, message: "Hello!")
    end
  end

  # --- TavernKit.build (Plan access) ---

  def test_build_returns_plan_with_blocks
    plan = TavernKit.build(
      character: @character_hash,
      user: "TestUser",
      message: "Hello!"
    )

    assert_instance_of TavernKit::Prompt::Plan, plan
    assert plan.blocks.is_a?(Array)
    assert plan.messages.is_a?(Array)
  end

  def test_build_with_full_options
    history = [
      TavernKit::Prompt::Message.new(role: :user, content: "Previous question"),
    ]

    plan = TavernKit.build(
      character: @character_hash,
      user: { name: "Alice", persona: "A tester" },
      message: "Hello!",
      history: history,
      preset: { main_prompt: "Custom main prompt." }
    )

    assert_instance_of TavernKit::Prompt::Plan, plan

    # Can access blocks
    assert plan.blocks.any? { |b| b.content.include?("Hello!") }

    # Can convert to messages
    messages = plan.to_messages
    assert messages.is_a?(Array)
    assert messages.any? { |m| m[:content].include?("Custom main prompt.") }
  end

  def test_build_exposes_lore_result
    lore_book_hash = {
      "name" => "Test Lore",
      "entries" => [
        {
          "uid" => 1,
          "keys" => ["test"],
          "content" => "Lore content here",
          "enabled" => true,
          "constant" => true,
          "position" => "after_char_defs",
        },
      ],
    }

    plan = TavernKit.build(
      character: @character_hash,
      user: "TestUser",
      message: "Hello with test keyword!",
      lore_books: [lore_book_hash]
    )

    # Lore result should be accessible
    assert_respond_to plan, :lore_result
  end

  # --- TavernKit.to_messages ---

  def test_to_messages_minimal
    messages = TavernKit.to_messages(
      character: @character_hash,
      user: "TestUser",
      message: "Hello!"
    )

    assert messages.is_a?(Array)
    assert messages.all? { |m| m.is_a?(Hash) && m.key?(:role) && m.key?(:content) }
    assert messages.any? { |m| m[:content].include?("Hello!") }
  end

  def test_to_messages_with_user_hash
    messages = TavernKit.to_messages(
      character: @character_hash,
      user: { name: "Alice", persona: "A curious traveler" },
      message: "Who are you?"
    )

    assert messages.is_a?(Array)
    # Check that persona is included somewhere in system messages
    system_content = messages.select { |m| m[:role] == "system" }.map { |m| m[:content] }.join
    assert system_content.include?("Alice") || system_content.include?("curious traveler")
  end

  def test_to_messages_with_preset_hash
    messages = TavernKit.to_messages(
      character: @character_hash,
      user: "TestUser",
      message: "Hello!",
      preset: { main_prompt: "Custom main prompt here.", prefer_char_prompt: false }
    )

    system_content = messages.select { |m| m[:role] == "system" }.map { |m| m[:content] }.join
    assert system_content.include?("Custom main prompt here.")
  end

  def test_to_messages_with_history
    history = [
      TavernKit::Prompt::Message.new(role: :user, content: "Previous question"),
      TavernKit::Prompt::Message.new(role: :assistant, content: "Previous answer"),
    ]

    messages = TavernKit.to_messages(
      character: @character_hash,
      user: "TestUser",
      message: "Follow-up",
      history: history
    )

    contents = messages.map { |m| m[:content] }
    assert contents.any? { |c| c.include?("Previous question") }
    assert contents.any? { |c| c.include?("Previous answer") }
    assert contents.any? { |c| c.include?("Follow-up") }
  end

  def test_to_messages_with_character_instance
    character = TavernKit.load_character(@character_hash)

    messages = TavernKit.to_messages(
      character: character,
      user: "TestUser",
      message: "Hello!"
    )

    assert messages.is_a?(Array)
    assert messages.any? { |m| m[:content].include?("TestBot") }
  end

  def test_to_messages_with_user_instance
    user = TavernKit::User.new(name: "DirectUser", persona: "Tester")

    messages = TavernKit.to_messages(
      character: @character_hash,
      user: user,
      message: "Testing direct User"
    )

    assert messages.is_a?(Array)
    system_content = messages.select { |m| m[:role] == "system" }.map { |m| m[:content] }.join
    assert system_content.include?("DirectUser") || system_content.include?("Tester")
  end

  def test_to_messages_with_preset_instance
    preset = TavernKit::Preset.new(main_prompt: "Preset instance test.", prefer_char_prompt: false)

    messages = TavernKit.to_messages(
      character: @character_hash,
      user: "TestUser",
      message: "Hello!",
      preset: preset
    )

    system_content = messages.select { |m| m[:role] == "system" }.map { |m| m[:content] }.join
    assert system_content.include?("Preset instance test.")
  end

  def test_to_messages_accepts_st_preset_hash
    st_preset_hash = {
      "prompts" => [
        { "identifier" => "main", "role" => 0, "content" => "ST Main" },
        { "identifier" => "jailbreak", "role" => 0, "content" => "ST PHI" },
        { "identifier" => "chatHistory", "marker" => true },
      ],
      "prompt_order" => [
        { "identifier" => "main", "enabled" => true },
        { "identifier" => "chatHistory", "enabled" => true },
      ],
    }

    messages = TavernKit.to_messages(
      character: @character_hash,
      user: "TestUser",
      message: "Hello!",
      preset: st_preset_hash
    )

    system_content = messages.select { |m| m[:role] == "system" }.map { |m| m[:content] }.join
    assert system_content.include?("ST Main")
  end

  def test_to_messages_auto_applies_squash_system_messages_for_openai
    preset = TavernKit::Preset.new(
      main_prompt: "M1",
      squash_system_messages: true,
      prompt_entries: [
        { "id" => "main_prompt", "pinned" => true },
        { "id" => "character_description", "pinned" => true },
        { "id" => "chat_history", "pinned" => true },
      ].map { |h| TavernKit::Prompt::PromptEntry.from_hash(h) },
    )

    messages = TavernKit.to_messages(
      character: @character_hash,
      user: "TestUser",
      message: "Hello!",
      preset: preset
    )

    system_messages = messages.select { |m| m[:role] == "system" }
    assert_equal 2, system_messages.length

    squashed = system_messages.find { |m| m[:content].to_s.include?("M1") }
    refute_nil squashed
    assert_includes squashed[:content], "M1"
    assert_includes squashed[:content], "A test character."

    # ST parity: new_chat_prompt is excluded from squashing.
    new_chat = system_messages.find { |m| m[:content].to_s.include?("[Start a new Chat]") }
    refute_nil new_chat
  end

  def test_to_messages_preserves_history_message_name_for_openai
    history = [
      TavernKit::Prompt::Message.new(role: :user, content: "Named history", name: "Alice"),
    ]

    preset = TavernKit::Preset.new(
      main_prompt: "M1",
      prompt_entries: [
        { "id" => "main_prompt", "pinned" => true },
        { "id" => "chat_history", "pinned" => true },
      ].map { |h| TavernKit::Prompt::PromptEntry.from_hash(h) },
    )

    messages = TavernKit.to_messages(
      character: @character_hash,
      user: "TestUser",
      message: "Hello!",
      history: history,
      preset: preset
    )

    named = messages.find { |m| m[:content] == "Named history" }
    refute_nil named
    assert_equal "Alice", named[:name]
  end

  def test_to_messages_handles_invalid_user_gracefully
    # Invalid user input is coerced to a default User
    messages = TavernKit.to_messages(
      character: @character_hash,
      user: 12345,
      message: "Hello!"
    )
    assert_kind_of Array, messages
  end

  def test_to_messages_raises_for_invalid_preset
    assert_raises(Errno::ENOENT) do
      TavernKit.to_messages(
        character: @character_hash,
        user: "TestUser",
        message: "Hello!",
        preset: "invalid"
      )
    end
  end

  # --- DSL Block Style Tests ---

  def test_build_with_block_sets_all_attributes
    card = TavernKit.load_character(@character_hash)
    chat_history = TavernKit::ChatHistory.wrap([
      TavernKit::Prompt::Message.new(role: :user, content: "Previous"),
    ])

    plan = TavernKit.build do
      character card
      user TavernKit::User.new(name: "BlockUser")
      preset TavernKit::Preset.new(main_prompt: "Block prompt.")
      history chat_history
      message "Block message"
    end

    messages = plan.to_messages
    contents = messages.map { |m| m[:content] }.join

    assert contents.include?("Block message")
    assert contents.include?("Block prompt.")
    assert contents.include?("Previous")
  end

  def test_to_messages_with_block_style
    card = TavernKit.load_character(@character_hash)

    messages = TavernKit.to_messages do
      character card
      user TavernKit::User.new(name: "BlockUser")
      message "Hello from block!"
    end

    assert messages.is_a?(Array)
    assert messages.any? { |m| m[:content].include?("Hello from block!") }
  end

  def test_build_with_lore_books
    lore_book = TavernKit::Lore::Book.from_hash({
      "name" => "Test Lore",
      "entries" => [
        {
          "uid" => 1,
          "keys" => ["magic"],
          "content" => "Magical lore content",
          "enabled" => true,
          "constant" => true,
          "position" => "after_char_defs",
        },
      ],
    }, source: :global)

    plan = TavernKit.build(
      character: @character_hash,
      user: "TestUser",
      message: "Tell me about magic!",
      lore_books: [lore_book]
    )

    messages = plan.to_messages
    contents = messages.map { |m| m[:content] }.join

    assert contents.include?("Magical lore content")
  end
end
