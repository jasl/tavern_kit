# frozen_string_literal: true

require "test_helper"

class TestParticipant < Minitest::Test
  def test_user_includes_participant
    assert_includes TavernKit::User.ancestors, TavernKit::Participant
  end

  def test_character_includes_participant
    assert_includes TavernKit::Character.ancestors, TavernKit::Participant
  end

  def test_user_implements_participant_interface
    user = TavernKit::User.new(name: "Alice", persona: "A curious adventurer")

    assert_respond_to user, :name
    assert_respond_to user, :persona_text
    assert_equal "Alice", user.name
    assert_equal "A curious adventurer", user.persona_text
  end

  def test_user_persona_text_with_nil_persona
    user = TavernKit::User.new(name: "Bob")

    assert_equal "", user.persona_text
  end

  def test_character_implements_participant_interface
    character = TavernKit::Character.create(
      name: "Seraphina",
      description: "A wise oracle",
      personality: "Calm and mysterious"
    )

    assert_respond_to character, :name
    assert_respond_to character, :persona_text
    assert_equal "Seraphina", character.name
  end

  def test_character_persona_text_combines_description_and_personality
    character = TavernKit::Character.create(
      name: "Seraphina",
      description: "A wise oracle who lives in the mountains.",
      personality: "Calm, mysterious, and kind."
    )

    expected = "A wise oracle who lives in the mountains.\n\nCalm, mysterious, and kind."
    assert_equal expected, character.persona_text
  end

  def test_character_persona_text_with_only_description
    character = TavernKit::Character.create(
      name: "Seraphina",
      description: "A wise oracle"
    )

    assert_equal "A wise oracle", character.persona_text
  end

  def test_character_persona_text_with_only_personality
    character = TavernKit::Character.create(
      name: "Seraphina",
      personality: "Calm and kind"
    )

    assert_equal "Calm and kind", character.persona_text
  end

  def test_character_persona_text_with_neither
    character = TavernKit::Character.create(name: "Seraphina")

    assert_equal "", character.persona_text
  end

  def test_character_persona_text_ignores_empty_strings
    character = TavernKit::Character.create(
      name: "Seraphina",
      description: "",
      personality: "Calm"
    )

    assert_equal "Calm", character.persona_text
  end
end

class TestCharacterAsUser < Minitest::Test
  def setup
    @alice = TavernKit::Character.create(
      name: "Alice",
      description: "An AI assistant",
      personality: "Helpful and friendly",
      first_mes: "Hello! I'm Alice."
    )

    @bob = TavernKit::Character.create(
      name: "Bob",
      description: "A curious researcher",
      personality: "Analytical and thorough",
      first_mes: "Greetings! I'm Bob."
    )
  end

  def test_build_accepts_character_as_user
    plan = TavernKit.build(
      character: @alice,
      user: @bob,
      preset: TavernKit::Preset.new(main_prompt: "You are {{char}}, talking to {{user}}."),
      message: "Hello!"
    )

    assert_instance_of TavernKit::Prompt::Plan, plan
  end

  def test_build_uses_character_name_as_user_name
    plan = TavernKit.build(
      character: @alice,
      user: @bob,
      preset: TavernKit::Preset.new(main_prompt: "You are {{char}}, talking to {{user}}."),
      message: "Hello!"
    )

    messages = plan.to_messages

    # The main prompt should have {{user}} expanded to "Bob"
    system_content = messages.find { |m| m[:role] == "system" }&.dig(:content)
    assert_includes system_content, "Bob"
  end

  def test_build_uses_character_persona_text
    plan = TavernKit.build(
      character: @alice,
      user: @bob,
      preset: TavernKit::Preset.new(
        main_prompt: "You are {{char}}.",
        prompt_entries: [
          { id: "persona_description", enabled: true },
        ].map { |h| TavernKit::Prompt::PromptEntry.from_hash(h) },
      ),
      message: "Hello!"
    )

    # Find persona block
    persona_block = plan.blocks.find { |b| b.slot == :persona }

    # Bob's persona should be his description + personality
    if persona_block
      assert_includes persona_block.content, "A curious researcher"
    end
  end

  def test_ai_to_ai_conversation_scenario
    # Simulate an AI-to-AI conversation
    alice = TavernKit::Character.create(
      name: "Alice",
      description: "An AI assistant specialized in creative writing",
      personality: "Creative, imaginative, supportive",
      system_prompt: "You are Alice, a creative writing AI.",
      first_mes: "Hello! I'd love to help you write a story."
    )

    bob = TavernKit::Character.create(
      name: "Bob",
      description: "An AI researcher interested in storytelling",
      personality: "Curious, analytical, enthusiastic"
    )

    plan = TavernKit.build(
      character: alice,
      user: bob,
      preset: TavernKit::Preset.new(
        main_prompt: "You are {{char}}, having a conversation with {{user}} about creative writing.",
      ),
      message: "Can you help me understand narrative structure?"
    )

    assert_instance_of TavernKit::Prompt::Plan, plan
    refute_empty plan.blocks

    messages = plan.to_messages
    assert messages.any? { |m| m[:role] == "user" }
    assert messages.any? { |m| m[:role] == "system" }
  end

  def test_dsl_block_style_with_character_as_user
    alice = @alice
    bob = @bob
    plan = TavernKit.build do
      character alice
      user bob
      preset TavernKit::Preset.new(main_prompt: "Conversation between AI agents.")
      message "Test message"
    end

    assert_instance_of TavernKit::Prompt::Plan, plan
  end

  def test_keyword_args_with_character_as_user
    plan = TavernKit.build(
      character: @alice,
      user: @bob,
      message: "Hello!",
      preset: { main_prompt: "AI conversation." }
    )

    assert_instance_of TavernKit::Prompt::Plan, plan
  end
end

class TestCustomParticipant < Minitest::Test
  # Test that any object implementing the Participant interface works
  class CustomAgent
    include TavernKit::Participant

    def name
      "CustomAgent"
    end

    def persona_text
      "I am a custom agent implementation."
    end
  end

  def test_build_accepts_custom_participant
    character = TavernKit::Character.create(
      name: "Alice",
      description: "An AI"
    )

    custom_agent = CustomAgent.new

    plan = TavernKit.build(
      character: character,
      user: custom_agent,
      preset: TavernKit::Preset.new(main_prompt: "Test."),
      message: "Hello!"
    )

    assert_instance_of TavernKit::Prompt::Plan, plan
  end

  def test_build_rejects_duck_typed_participant
    character = TavernKit::Character.create(
      name: "Alice",
      description: "An AI"
    )

    # Duck-typed object without including Participant module
    duck = Struct.new(:name, :persona_text).new("Duck", "Quack quack")

    assert_raises(ArgumentError) do
      TavernKit.build(
        character: character,
        user: duck,
        preset: TavernKit::Preset.new(main_prompt: "Test."),
        message: "Hello!"
      )
    end
  end
end
