# frozen_string_literal: true

require "test_helper"

class PromptBuilderTest < ActiveSupport::TestCase
  setup do
    @conversation = conversations(:general_main)
    @ai_chat_conversation = conversations(:ai_chat_main)
  end

  test "initializes with conversation" do
    builder = PromptBuilder.new(@conversation)

    assert_equal @conversation, builder.conversation
    assert_equal @conversation.space, builder.space
    assert_nil builder.user_message
    assert_not_nil builder.speaker
  end

  test "initializes with user message" do
    builder = PromptBuilder.new(@conversation, user_message: "Hello!")

    assert_equal "Hello!", builder.user_message
  end

  test "initializes with specific speaker" do
    speaker = space_memberships(:character_in_general)
    builder = PromptBuilder.new(@conversation, speaker: speaker)

    assert_equal speaker, builder.speaker
  end

  test "auto-selects speaker from conversation" do
    builder = PromptBuilder.new(@conversation)

    assert builder.speaker.character?
  end

  test "builds prompt plan (memoized)" do
    builder = PromptBuilder.new(@conversation)

    plan1 = builder.build
    plan2 = builder.build

    assert_instance_of TavernKit::Prompt::Plan, plan1
    assert_same plan1, plan2
  end

  test "raises error when space has no AI characters" do
    space = Spaces::Playground.create!(name: "Empty Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)

    builder = PromptBuilder.new(conversation)

    error = assert_raises(PromptBuilder::PromptBuilderError) { builder.build }
    assert_match(/no AI characters/i, error.message)
  end

  test "converts to OpenAI messages format" do
    builder = PromptBuilder.new(@conversation, user_message: "Hello!")
    messages = builder.to_messages

    assert_kind_of Array, messages
    assert messages.any?

    first = messages.first
    assert first.key?(:role)
    assert first.key?(:content)
  end

  test "converts to text dialect" do
    builder = PromptBuilder.new(@conversation, user_message: "Hello!")
    result = builder.to_messages(dialect: :text)

    assert_kind_of Hash, result
    assert result[:prompt].present?
  end

  test "detects single character chat as non-group" do
    space = Spaces::Playground.create!(name: "Single Char Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    builder = PromptBuilder.new(conversation)

    assert_not builder.group_chat?
  end

  test "detects conversation with multiple visible participants as group" do
    # Use ai_chat conversation which has 3 memberships: 1 human + 2 characters
    builder = PromptBuilder.new(@ai_chat_conversation)

    assert builder.group_chat?
  end

  test "detects multiple character conversation as group" do
    builder = PromptBuilder.new(@ai_chat_conversation)

    assert builder.group_chat?
  end

  test "includes existing messages in history" do
    builder = PromptBuilder.new(@conversation)
    messages = builder.to_messages
    contents = messages.map { |m| m.fetch(:content) }.join(" ")

    assert contents.present?
  end

  test "includes user message when provided" do
    user_message = "Unique test message #{SecureRandom.hex(8)}"
    builder = PromptBuilder.new(@conversation, user_message: user_message)
    messages = builder.to_messages

    message_contents = messages.map { |m| m.fetch(:content) }
    assert message_contents.any? { |c| c&.include?(user_message) }
  end

  test "converts character participant to TavernKit character" do
    participant = space_memberships(:character_in_general)
    tk_participant = PromptBuilding::ParticipantAdapter.to_participant(participant)

    assert_instance_of TavernKit::Character, tk_participant
    assert_equal participant.character.name, tk_participant.name
  end

  test "converts user participant to TavernKit user" do
    participant = space_memberships(:admin_in_general)
    tk_participant = PromptBuilding::ParticipantAdapter.to_participant(participant)

    assert_instance_of TavernKit::User, tk_participant
    assert_equal participant.user.name, tk_participant.name
  end

  test "uses provided preset" do
    preset = TavernKit::Preset.new(main_prompt: "Custom system prompt for testing.", context_window_tokens: 4096)
    builder = PromptBuilder.new(@conversation, preset: preset)
    messages = builder.to_messages

    system_messages = messages.select { |m| m.fetch(:role) == "system" }
    system_content = system_messages.map { |m| m.fetch(:content) }.join(" ")

    assert_match(/Custom system prompt/i, system_content)
  end

  test "applies space scenario_override to effective character participant" do
    space = Spaces::Playground.create!(name: "Scenario Override Space", owner: users(:admin), prompt_settings: { "scenario_override" => "OVERRIDE SCENARIO" })
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    builder = PromptBuilder.new(conversation, speaker: speaker)
    participant = builder.send(:effective_character_participant)

    assert_includes participant.data.scenario.to_s, "OVERRIDE SCENARIO"
  end

  test "applies space preset main_prompt override to output" do
    space =
      Spaces::Playground.create!(
        name: "Preset Override Space",
        owner: users(:admin),
        prompt_settings: { "preset" => { "main_prompt" => "CUSTOM MAIN PROMPT" } }
      )

    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    builder = PromptBuilder.new(conversation, speaker: speaker, user_message: "Hello!")
    messages = builder.to_messages
    contents = messages.map { |m| m.fetch(:content) }.join("\n")

    assert_includes contents, "CUSTOM MAIN PROMPT"
  end

  test "applies new_chat_prompt and replace_empty_message from space preset to output" do
    user = users(:admin)

    space =
      Spaces::Playground.create!(
        name: "Utility Prompt Space",
        owner: user,
        prompt_settings: {
          "preset" => {
            "new_chat_prompt" => "NEW CHAT",
            "replace_empty_message" => "EMPTY",
          },
        }
      )

    conversation = space.conversations.create!(title: "Main")
    human = space.space_memberships.create!(kind: "human", role: "owner", user: user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    conversation.messages.create!(space_membership: human, role: "user", content: "Hi")
    conversation.messages.create!(space_membership: speaker, role: "assistant", content: "Hello")

    builder = PromptBuilder.new(conversation, speaker: speaker, user_message: "")
    messages = builder.to_messages
    contents = messages.map { |m| m.fetch(:content) }

    new_idx = contents.index("NEW CHAT")
    hi_idx = contents.index("Hi")
    empty_idx = contents.index("EMPTY")

    refute_nil new_idx
    refute_nil hi_idx
    refute_nil empty_idx
    assert new_idx < hi_idx, "new_chat_prompt should precede chat history"
  end

  test "applies membership generation token settings to effective preset" do
    space = Spaces::Playground.create!(name: "Token Budget Space", owner: users(:admin), prompt_settings: {})
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)

    speaker =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v2),
        position: 1,
        settings: {
          "llm" => {
            "providers" => {
              "openai_compatible" => {
                "generation" => {
                  "max_context_tokens" => 2048,
                  "max_response_tokens" => 256,
                },
              },
            },
          },
        }
      )

    builder = PromptBuilder.new(conversation, speaker: speaker, user_message: "Hello!")
    preset = builder.send(:effective_preset)

    assert_equal 2048, preset.context_window_tokens
    assert_equal 256, preset.reserved_response_tokens
  end

  test "converts space world_info budget_percent into TavernKit preset token budget" do
    space = Spaces::Playground.create!(name: "World Info Budget Space", owner: users(:admin), prompt_settings: { "world_info" => { "budget_percent" => 10 } })
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)

    speaker =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v2),
        position: 1,
        settings: {
          "llm" => {
            "providers" => {
              "openai_compatible" => {
                "generation" => {
                  "max_context_tokens" => 1000,
                  "max_response_tokens" => 100,
                },
              },
            },
          },
        }
      )

    builder = PromptBuilder.new(conversation, speaker: speaker)
    preset = builder.send(:effective_preset)

    assert_equal 90, preset.world_info_budget
  end

  test "swap mode includes only active speaker definitions" do
    space = Spaces::Playground.create!(name: "Swap Space", owner: users(:admin), card_handling_mode: "swap")
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)

    alice = Character.create!(
      name: "Alice",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Alice", "description" => "ALICE DESCRIPTION", "first_mes" => "Hi" }
    )

    bob = Character.create!(
      name: "Bob",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Bob", "description" => "BOB DESCRIPTION", "first_mes" => "Hello" }
    )

    alice_participant = space.space_memberships.create!(kind: "character", role: "member", character: alice, position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: bob, position: 2)

    builder = PromptBuilder.new(conversation, speaker: alice_participant)
    participant = builder.send(:effective_character_participant)

    assert_includes participant.data.description.to_s, "ALICE DESCRIPTION"
    assert_not_includes participant.data.description.to_s, "BOB DESCRIPTION"
  end

  test "join_include_non_participating includes non-participating participants in joined fields" do
    space = Spaces::Playground.create!(name: "Join Include Non-Participating Space", owner: users(:admin), card_handling_mode: "append_disabled")
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)

    alice = Character.create!(
      name: "Alice",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Alice", "description" => "ALICE DESCRIPTION", "first_mes" => "Hi" }
    )

    bob = Character.create!(
      name: "Bob",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Bob", "description" => "BOB DESCRIPTION", "first_mes" => "Hello" }
    )

    alice_participant = space.space_memberships.create!(kind: "character", role: "member", character: alice, position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: bob, position: 2, participation: "muted")

    builder = PromptBuilder.new(conversation, speaker: alice_participant)
    participant = builder.send(:effective_character_participant)

    assert_includes participant.data.description.to_s, "ALICE DESCRIPTION"
    assert_includes participant.data.description.to_s, "BOB DESCRIPTION"
  end

  test "join_exclude_non_participating excludes non-participating participants unless they are the speaker" do
    space = Spaces::Playground.create!(name: "Join Exclude Non-Participating Space", owner: users(:admin), card_handling_mode: "append")
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)

    alice = Character.create!(
      name: "Alice",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Alice", "description" => "ALICE DESCRIPTION", "first_mes" => "Hi" }
    )

    bob = Character.create!(
      name: "Bob",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Bob", "description" => "BOB DESCRIPTION", "first_mes" => "Hello" }
    )

    alice_participant = space.space_memberships.create!(kind: "character", role: "member", character: alice, position: 1)
    bob_participant = space.space_memberships.create!(kind: "character", role: "member", character: bob, position: 2, participation: "muted")

    builder = PromptBuilder.new(conversation, speaker: alice_participant)
    participant = builder.send(:effective_character_participant)
    assert_includes participant.data.description.to_s, "ALICE DESCRIPTION"
    assert_not_includes participant.data.description.to_s, "BOB DESCRIPTION"

    builder = PromptBuilder.new(conversation, speaker: bob_participant)
    participant = builder.send(:effective_character_participant)
    assert_includes participant.data.description.to_s, "BOB DESCRIPTION"
  end

  test "join_prefix and join_suffix replace {{char}} and <FIELDNAME> per segment" do
    space =
      Spaces::Playground.create!(
        name: "Join Prefix/Suffix Space",
        owner: users(:admin),
        card_handling_mode: "append_disabled",
        prompt_settings: {
          "join_prefix" => "<<{{char}}:<FIELDNAME>>",
          "join_suffix" => "<</{{char}}:<FIELDNAME>>",
          "scenario_override" => "OVERRIDE SCENARIO",
        }
      )

    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)

    alice = Character.create!(
      name: "Alice",
      spec_version: 2,
      status: "ready",
      data: {
        "name" => "Alice",
        "description" => "ALICE DESCRIPTION",
        "scenario" => "ALICE SCENARIO",
        "extensions" => { "depth_prompt" => { "prompt" => "ALICE DEPTH" } },
        "first_mes" => "Hi",
      }
    )

    bob = Character.create!(
      name: "Bob",
      spec_version: 2,
      status: "ready",
      data: {
        "name" => "Bob",
        "description" => "BOB DESCRIPTION",
        "scenario" => "BOB SCENARIO",
        "extensions" => { "depth_prompt" => { "prompt" => "BOB DEPTH" } },
        "first_mes" => "Hello",
      }
    )

    alice_participant = space.space_memberships.create!(kind: "character", role: "member", character: alice, position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: bob, position: 2)

    builder = PromptBuilder.new(conversation, speaker: alice_participant)
    participant = builder.send(:effective_character_participant)

    assert_includes participant.data.description.to_s, "<<Alice:description>>"
    assert_includes participant.data.description.to_s, "<</Alice:description>>"
    assert_includes participant.data.description.to_s, "<<Bob:description>>"
    assert_includes participant.data.description.to_s, "<</Bob:description>>"

    assert_includes participant.data.scenario.to_s, "<<Alice:scenario>>OVERRIDE SCENARIO<</Alice:scenario>>"
    assert_includes participant.data.scenario.to_s, "<<Bob:scenario>>OVERRIDE SCENARIO<</Bob:scenario>>"
    assert_not_includes participant.data.scenario.to_s, "ALICE SCENARIO"
    assert_not_includes participant.data.scenario.to_s, "BOB SCENARIO"

    depth_prompt = participant.data.extensions.dig("depth_prompt", "prompt")
    assert_includes depth_prompt.to_s, "<<Alice:depth_prompt>>ALICE DEPTH<</Alice:depth_prompt>>"
    assert_includes depth_prompt.to_s, "<<Bob:depth_prompt>>BOB DEPTH<</Bob:depth_prompt>>"
  end

  test "collects lore books from characters" do
    character_with_lorebook = Character.create!(
      name: "Lorebook Character",
      spec_version: 2,
      status: "ready",
      data: {
        "name" => "Lorebook Character",
        "description" => "Test",
        "personality" => "Test",
        "character_book" => {
          "name" => "Test Lorebook",
          "entries" => [
            {
              "keys" => ["test", "keyword"],
              "content" => "This is test lore content.",
              "enabled" => true,
              "position" => "before_char",
            },
          ],
        },
      }
    )

    space = Spaces::Playground.create!(name: "Lore Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: character_with_lorebook, position: 1)

    builder = PromptBuilder.new(conversation)
    plan = builder.build

    assert_instance_of TavernKit::Prompt::Plan, plan
  end

  test "chat history adapter iterates over messages" do
    relation = @conversation.messages.ordered.with_participant
    history = PromptBuilding::MessageHistory.new(relation)

    out = history.to_a
    assert_equal relation.count, out.size

    out.each do |msg|
      assert_instance_of TavernKit::Prompt::Message, msg
      assert_includes %i[user assistant system], msg.role
      assert msg.content.present?
    end
  end

  test "chat history adapter converts message attributes" do
    relation = @conversation.messages.ordered.with_participant
    history = PromptBuilding::MessageHistory.new(relation)

    history_messages = history.to_a
    original_messages = relation.to_a

    assert_equal original_messages.size, history_messages.size

    original_messages.each_with_index do |original, idx|
      converted = history_messages[idx]

      assert_equal original.role.to_sym, converted.role
      assert_equal original.plain_text_content, converted.content
      assert_equal original.sender_display_name, converted.name
      assert_equal original.created_at.to_i, converted.send_date
    end
  end

  # Tests for removed membership exclusion (status: removed)

  test "group_context excludes removed characters" do
    space = Spaces::Playground.create!(name: "Removed Member Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)

    alice = Character.create!(
      name: "Alice",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Alice", "description" => "Alice description", "first_mes" => "Hi" }
    )

    bob = Character.create!(
      name: "Bob",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Bob", "description" => "Bob description", "first_mes" => "Hello" }
    )

    charlie = Character.create!(
      name: "Charlie",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Charlie", "description" => "Charlie description", "first_mes" => "Hey" }
    )

    alice_participant = space.space_memberships.create!(kind: "character", role: "member", character: alice, position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: bob, position: 2, participation: "muted")
    space.space_memberships.create!(kind: "character", role: "member", character: charlie, position: 3, status: "removed")

    builder = PromptBuilder.new(conversation, speaker: alice_participant)
    group_ctx = builder.send(:group_context)

    assert_includes group_ctx.members, "Alice"
    assert_includes group_ctx.muted, "Bob"
    assert_not_includes group_ctx.members, "Charlie"
    assert_not_includes group_ctx.muted, "Charlie"
  end

  test "lore_books excludes removed characters" do
    active_char = Character.create!(
      name: "Active Lore Char",
      spec_version: 2,
      status: "ready",
      data: {
        "name" => "Active Lore Char",
        "description" => "Test",
        "character_book" => {
          "name" => "Active Lorebook",
          "entries" => [
            { "keys" => ["active"], "content" => "Active lore content.", "enabled" => true, "position" => "before_char" },
          ],
        },
      }
    )

    removed_char = Character.create!(
      name: "Removed Lore Char",
      spec_version: 2,
      status: "ready",
      data: {
        "name" => "Removed Lore Char",
        "description" => "Test",
        "character_book" => {
          "name" => "Removed Lorebook",
          "entries" => [
            { "keys" => ["removed"], "content" => "Removed lore content.", "enabled" => true, "position" => "before_char" },
          ],
        },
      }
    )

    space = Spaces::Playground.create!(name: "Lore Exclusion Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: active_char, position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: removed_char, position: 2, status: "removed")

    builder = PromptBuilder.new(conversation)
    books = builder.send(:lore_books)

    book_names = books.map(&:name)
    assert_includes book_names, "Active Lorebook"
    assert_not_includes book_names, "Removed Lorebook"
  end

  test "join_include_muted excludes removed characters" do
    space = Spaces::Playground.create!(name: "Join Include Muted Removed Space", owner: users(:admin), card_handling_mode: "append_disabled")
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)

    alice = Character.create!(
      name: "Alice",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Alice", "description" => "ALICE_ACTIVE_DESC", "first_mes" => "Hi" }
    )

    bob = Character.create!(
      name: "Bob",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Bob", "description" => "BOB_MUTED_DESC", "first_mes" => "Hello" }
    )

    charlie = Character.create!(
      name: "Charlie",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Charlie", "description" => "CHARLIE_REMOVED_DESC", "first_mes" => "Hey" }
    )

    alice_participant = space.space_memberships.create!(kind: "character", role: "member", character: alice, position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: bob, position: 2, participation: "muted")
    space.space_memberships.create!(kind: "character", role: "member", character: charlie, position: 3, status: "removed")

    builder = PromptBuilder.new(conversation, speaker: alice_participant)
    participant = builder.send(:effective_character_participant)
    description = participant.data.description.to_s

    assert_includes description, "ALICE_ACTIVE_DESC"
    assert_includes description, "BOB_MUTED_DESC"
    assert_not_includes description, "CHARLIE_REMOVED_DESC"
  end

  test "join_exclude_muted excludes removed characters" do
    space = Spaces::Playground.create!(name: "Join Exclude Muted Removed Space", owner: users(:admin), card_handling_mode: "append")
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)

    alice = Character.create!(
      name: "Alice",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Alice", "description" => "ALICE_ACTIVE_DESC", "first_mes" => "Hi" }
    )

    bob = Character.create!(
      name: "Bob",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Bob", "description" => "BOB_MUTED_DESC", "first_mes" => "Hello" }
    )

    charlie = Character.create!(
      name: "Charlie",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Charlie", "description" => "CHARLIE_REMOVED_DESC", "first_mes" => "Hey" }
    )

    alice_participant = space.space_memberships.create!(kind: "character", role: "member", character: alice, position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: bob, position: 2, participation: "muted")
    space.space_memberships.create!(kind: "character", role: "member", character: charlie, position: 3, status: "removed")

    builder = PromptBuilder.new(conversation, speaker: alice_participant)
    participant = builder.send(:effective_character_participant)
    description = participant.data.description.to_s

    assert_includes description, "ALICE_ACTIVE_DESC"
    assert_not_includes description, "BOB_MUTED_DESC"
    assert_not_includes description, "CHARLIE_REMOVED_DESC"
  end

  # --- Context visibility tests (excluded_from_prompt) ---

  test "excludes messages with excluded_from_prompt flag from prompt" do
    # Create messages in conversation
    message1 = @conversation.messages.create!(
      space_membership: space_memberships(:admin_in_general),
      role: "user",
      content: "This message should be included"
    )

    excluded_message = @conversation.messages.create!(
      space_membership: space_memberships(:character_in_general),
      role: "assistant",
      content: "This message should be EXCLUDED",
      excluded_from_prompt: true
    )

    message3 = @conversation.messages.create!(
      space_membership: space_memberships(:admin_in_general),
      role: "user",
      content: "This message should also be included"
    )

    builder = PromptBuilder.new(@conversation)
    messages = builder.to_messages

    # Find the message contents in the prompt
    contents = messages.map { |m| m[:content] }.join("\n")

    assert_includes contents, "This message should be included"
    assert_includes contents, "This message should also be included"
    assert_not_includes contents, "This message should be EXCLUDED"
  ensure
    # Clean up
    message1&.destroy
    excluded_message&.destroy
    message3&.destroy
  end

  test "MessageHistory skips excluded messages" do
    # Create messages in conversation
    message1 = @conversation.messages.create!(
      space_membership: space_memberships(:admin_in_general),
      role: "user",
      content: "Included message"
    )

    excluded_message = @conversation.messages.create!(
      space_membership: space_memberships(:character_in_general),
      role: "assistant",
      content: "Excluded message",
      excluded_from_prompt: true
    )

    history = PromptBuilding::MessageHistory.new(
      @conversation.messages.ordered.with_participant
    )

    included_contents = history.map(&:content)

    assert_includes included_contents, "Included message"
    assert_not_includes included_contents, "Excluded message"
  ensure
    message1&.destroy
    excluded_message&.destroy
  end

  test "MessageHistory#size matches yielded message count when excluded messages exist" do
    # Create a mix of included and excluded messages
    @conversation.messages.create!(
      space_membership: space_memberships(:admin_in_general),
      role: "user",
      content: "Message 1"
    )

    @conversation.messages.create!(
      space_membership: space_memberships(:character_in_general),
      role: "assistant",
      content: "Excluded",
      excluded_from_prompt: true
    )

    @conversation.messages.create!(
      space_membership: space_memberships(:admin_in_general),
      role: "user",
      content: "Message 2"
    )

    history = PromptBuilding::MessageHistory.new(
      @conversation.messages.ordered.with_participant
    )

    messages_in_history = history.to_a
    excluded_in_iteration = messages_in_history.none? { |m| m.content == "Excluded" }

    assert excluded_in_iteration, "Excluded message should not appear in iteration"
    assert_equal messages_in_history.size, history.size
  end

  # --- Conversation-level Author's Note tests ---

  test "conversation authors_note overrides space preset authors_note" do
    # Create space with preset authors_note
    space = Spaces::Playground.create!(
      name: "Authors Note Space",
      owner: users(:admin),
      prompt_settings: { "preset" => { "authors_note" => "SPACE_LEVEL_AUTHORS_NOTE" } }
    )

    conversation = space.conversations.create!(
      title: "Main",
      authors_note: "CONVERSATION_LEVEL_AUTHORS_NOTE"
    )

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    builder = PromptBuilder.new(conversation, speaker: speaker)
    preset = builder.send(:effective_preset)

    # The conversation-level authors_note should override the space-level one
    assert_equal "CONVERSATION_LEVEL_AUTHORS_NOTE", preset.authors_note
  end

  test "space preset authors_note is used when conversation authors_note is blank" do
    # Create space with preset authors_note
    space = Spaces::Playground.create!(
      name: "Authors Note Fallback Space",
      owner: users(:admin),
      prompt_settings: { "preset" => { "authors_note" => "SPACE_LEVEL_AUTHORS_NOTE" } }
    )

    # Conversation without authors_note
    conversation = space.conversations.create!(title: "Main", authors_note: nil)

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    builder = PromptBuilder.new(conversation, speaker: speaker)
    preset = builder.send(:effective_preset)

    # Falls back to space-level authors_note
    assert_equal "SPACE_LEVEL_AUTHORS_NOTE", preset.authors_note
  end

  test "conversation authors_note with empty string falls back to space preset" do
    space = Spaces::Playground.create!(
      name: "Authors Note Empty Space",
      owner: users(:admin),
      prompt_settings: { "preset" => { "authors_note" => "SPACE_AUTHORS_NOTE" } }
    )

    # Conversation with empty string (should fall back)
    conversation = space.conversations.create!(title: "Main", authors_note: "")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    builder = PromptBuilder.new(conversation, speaker: speaker)
    preset = builder.send(:effective_preset)

    # Falls back to space-level since conversation.authors_note is blank
    assert_equal "SPACE_AUTHORS_NOTE", preset.authors_note
  end

  # --- Character-linked lorebooks tests ---

  test "lore_books collects primary character-linked lorebook" do
    # Create character with a linked lorebook
    character = Character.create!(
      name: "Linked Lorebook Character",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Linked Lorebook Character", "description" => "Test", "first_mes" => "Hi" }
    )

    lorebook = Lorebook.create!(name: "Primary Linked Lorebook")
    lorebook.entries.create!(
      uid: "entry1",
      keys: ["magic"],
      content: "Primary linked lorebook content about magic.",
      enabled: true
    )

    CharacterLorebook.create!(character: character, lorebook: lorebook, source: "primary", enabled: true)

    space = Spaces::Playground.create!(name: "Linked Lorebook Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: character, position: 1)

    builder = PromptBuilder.new(conversation)
    books = builder.send(:lore_books)

    book_names = books.map(&:name)
    assert_includes book_names, "Primary Linked Lorebook"
  end

  test "lore_books collects additional character-linked lorebooks" do
    character = Character.create!(
      name: "Additional Lorebooks Character",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Additional Lorebooks Character", "description" => "Test", "first_mes" => "Hi" }
    )

    lorebook1 = Lorebook.create!(name: "Additional Lorebook 1")
    lorebook1.entries.create!(uid: "e1", keys: ["dragon"], content: "Dragon lore", enabled: true)

    lorebook2 = Lorebook.create!(name: "Additional Lorebook 2")
    lorebook2.entries.create!(uid: "e2", keys: ["elf"], content: "Elf lore", enabled: true)

    CharacterLorebook.create!(character: character, lorebook: lorebook1, source: "additional", priority: 0, enabled: true)
    CharacterLorebook.create!(character: character, lorebook: lorebook2, source: "additional", priority: 1, enabled: true)

    space = Spaces::Playground.create!(name: "Additional Lorebooks Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: character, position: 1)

    builder = PromptBuilder.new(conversation)
    books = builder.send(:lore_books)

    book_names = books.map(&:name)
    assert_includes book_names, "Additional Lorebook 1"
    assert_includes book_names, "Additional Lorebook 2"
  end

  test "lore_books excludes disabled character-linked lorebooks" do
    character = Character.create!(
      name: "Disabled Lorebook Character",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Disabled Lorebook Character", "description" => "Test", "first_mes" => "Hi" }
    )

    enabled_lorebook = Lorebook.create!(name: "Enabled Lorebook")
    enabled_lorebook.entries.create!(uid: "e1", keys: ["test"], content: "Enabled content", enabled: true)

    disabled_lorebook = Lorebook.create!(name: "Disabled Lorebook")
    disabled_lorebook.entries.create!(uid: "e2", keys: ["test2"], content: "Disabled content", enabled: true)

    CharacterLorebook.create!(character: character, lorebook: enabled_lorebook, source: "additional", enabled: true)
    CharacterLorebook.create!(character: character, lorebook: disabled_lorebook, source: "additional", enabled: false)

    space = Spaces::Playground.create!(name: "Disabled Lorebook Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: character, position: 1)

    builder = PromptBuilder.new(conversation)
    books = builder.send(:lore_books)

    book_names = books.map(&:name)
    assert_includes book_names, "Enabled Lorebook"
    assert_not_includes book_names, "Disabled Lorebook"
  end

  test "lore_books combines embedded and linked character lorebooks" do
    character = Character.create!(
      name: "Combined Lorebooks Character",
      spec_version: 2,
      status: "ready",
      data: {
        "name" => "Combined Lorebooks Character",
        "description" => "Test",
        "first_mes" => "Hi",
        "character_book" => {
          "name" => "Embedded Lorebook",
          "entries" => [
            { "keys" => ["embedded"], "content" => "Embedded lore content.", "enabled" => true, "position" => "before_char" },
          ],
        },
      }
    )

    linked_lorebook = Lorebook.create!(name: "Linked Lorebook")
    linked_lorebook.entries.create!(uid: "link1", keys: ["linked"], content: "Linked lore content", enabled: true)

    CharacterLorebook.create!(character: character, lorebook: linked_lorebook, source: "primary", enabled: true)

    space = Spaces::Playground.create!(name: "Combined Lorebooks Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: character, position: 1)

    builder = PromptBuilder.new(conversation)
    books = builder.send(:lore_books)

    book_names = books.map(&:name)
    assert_includes book_names, "Embedded Lorebook"
    assert_includes book_names, "Linked Lorebook"
  end

  test "lore_books excludes linked lorebooks from removed characters" do
    active_char = Character.create!(
      name: "Active Linked Char",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Active Linked Char", "description" => "Test", "first_mes" => "Hi" }
    )

    removed_char = Character.create!(
      name: "Removed Linked Char",
      spec_version: 2,
      status: "ready",
      data: { "name" => "Removed Linked Char", "description" => "Test", "first_mes" => "Hi" }
    )

    active_lorebook = Lorebook.create!(name: "Active Character Lorebook")
    active_lorebook.entries.create!(uid: "a1", keys: ["active"], content: "Active lore", enabled: true)

    removed_lorebook = Lorebook.create!(name: "Removed Character Lorebook")
    removed_lorebook.entries.create!(uid: "r1", keys: ["removed"], content: "Removed lore", enabled: true)

    CharacterLorebook.create!(character: active_char, lorebook: active_lorebook, source: "primary", enabled: true)
    CharacterLorebook.create!(character: removed_char, lorebook: removed_lorebook, source: "primary", enabled: true)

    space = Spaces::Playground.create!(name: "Removed Linked Lorebook Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: active_char, position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: removed_char, position: 2, status: "removed")

    builder = PromptBuilder.new(conversation)
    books = builder.send(:lore_books)

    book_names = books.map(&:name)
    assert_includes book_names, "Active Character Lorebook"
    assert_not_includes book_names, "Removed Character Lorebook"
  end
end
