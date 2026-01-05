# frozen_string_literal: true

require "test_helper"

class SpeakerSelectorTest < ActiveSupport::TestCase
  setup do
    @space = Spaces::Playground.create!(name: "Speaker Selector Test Space", owner: users(:admin), reply_order: "natural")
    @conversation = @space.conversations.create!(title: "Main")
    @user_membership = @space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    @ai_character = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
  end

  test "select_ai_character_only returns an AI character" do
    selector = SpeakerSelector.new(@conversation)

    speaker = selector.select_ai_character_only

    assert_equal @ai_character, speaker
  end

  test "select_ai_character_only excludes copilot users (human with persona)" do
    # Enable copilot mode on the user membership
    @user_membership.update!(
      character: characters(:ready_v3),
      copilot_mode: "full",
      copilot_remaining_steps: 5
    )

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_ai_character_only

    assert_equal @ai_character, speaker
    assert_not_equal @user_membership, speaker
  end

  test "select_ai_character_only with exclude_participant_id excludes that membership id" do
    second_ai = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_ai_character_only(exclude_participant_id: @ai_character.id)

    assert_equal second_ai, speaker
  end

  test "select_ai_character_only returns nil when all AI characters are excluded" do
    selector = SpeakerSelector.new(@conversation)

    speaker = selector.select_ai_character_only(exclude_participant_id: @ai_character.id)

    assert_nil speaker
  end

  test "select_ai_character_only returns nil for manual reply_order" do
    @space.update!(reply_order: "manual")

    selector = SpeakerSelector.new(@conversation)

    assert_nil selector.select_ai_character_only
  end

  test "select_for_user_turn returns first eligible speaker" do
    selector = SpeakerSelector.new(@conversation)

    speaker = selector.select_for_user_turn

    assert_equal @ai_character, speaker
  end

  test "select_for_user_turn includes copilot users when no AI characters exist" do
    @ai_character.remove!(by_user: @user)

    # Enable copilot mode on the user membership
    @user_membership.update!(
      character: characters(:ready_v3),
      copilot_mode: "full",
      copilot_remaining_steps: 5
    )

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

    assert_equal @user_membership, speaker
  end

  test "natural selects mentioned character when mentioned in last user message" do
    # Create a character with a unique name to avoid word collisions
    bob_char = Character.create!(
      name: "Bob",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Bob", "description" => "Test" }
    )
    bob = @space.space_memberships.create!(kind: "character", role: "member", character: bob_char, position: 2)

    # Set talkativeness to 0 so only mentions can activate
    @ai_character.update!(talkativeness_factor: 0)
    bob.update!(talkativeness_factor: 0)

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hey Bob, what do you think about this?"
    )

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

    assert_equal bob, speaker
  end

  test "natural mention detection is case insensitive" do
    # Create a character with a unique name to avoid word collisions
    charlie_char = Character.create!(
      name: "Charlie",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Charlie", "description" => "Test" }
    )
    charlie = @space.space_memberships.create!(kind: "character", role: "member", character: charlie_char, position: 2)

    # Set talkativeness to 0 so only mentions can activate
    @ai_character.update!(talkativeness_factor: 0)
    charlie.update!(talkativeness_factor: 0)

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "hey charlie, what's up?"
    )

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

    assert_equal charlie, speaker
  end

  test "natural falls back to round-robin when no mention and no talkativeness activation" do
    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    # Set talkativeness to 0 so only mentions or round-robin can select
    @ai_character.update!(talkativeness_factor: 0)
    char_b.update!(talkativeness_factor: 0)

    @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello everyone!")
    @conversation.messages.create!(space_membership: @ai_character, role: "assistant", content: "Hi there!")

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

    # With no mentions and talkativeness=0, round-robin selects char_b (next after @ai_character)
    assert_equal char_b, speaker
  end

  test "pooled does not repeat speaker in same user epoch" do
    @space.update!(reply_order: "pooled")

    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello everyone!")

    selector = SpeakerSelector.new(@conversation)
    first_speaker = selector.select_for_user_turn
    assert_includes [@ai_character, char_b], first_speaker

    @conversation.messages.create!(space_membership: first_speaker, role: "assistant", content: "A1")

    selector2 = SpeakerSelector.new(@conversation.reload)
    second_speaker = selector2.select_for_auto_mode(previous_speaker: first_speaker)

    assert_includes [@ai_character, char_b], second_speaker
    assert_not_equal first_speaker.id, second_speaker.id
  end

  test "pooled returns nil when pool is exhausted" do
    @space.update!(reply_order: "pooled")

    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello!")

    selector = SpeakerSelector.new(@conversation)
    first = selector.select_for_user_turn
    @conversation.messages.create!(space_membership: first, role: "assistant", content: "A1")

    selector2 = SpeakerSelector.new(@conversation.reload)
    second = selector2.select_for_auto_mode(previous_speaker: first)
    @conversation.messages.create!(space_membership: second, role: "assistant", content: "A2")

    selector3 = SpeakerSelector.new(@conversation.reload)
    third = selector3.select_for_auto_mode(previous_speaker: second)

    assert_nil third
  end

  # ──────────────────────────────────────────────────────────────────
  # Whole-word matching tests
  # ──────────────────────────────────────────────────────────────────

  test "natural uses whole-word matching and does not match partial names" do
    # Create a character named "Alice"
    alice_char = Character.create!(
      name: "Alice",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Alice", "description" => "Test" }
    )
    alice = @space.space_memberships.create!(kind: "character", role: "member", character: alice_char, position: 2)

    # Create a character named "Alicex" - should NOT be matched by "Alice"
    alicex_char = Character.create!(
      name: "Alicex",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Alicex", "description" => "Test" }
    )
    alicex = @space.space_memberships.create!(kind: "character", role: "member", character: alicex_char, position: 3)

    # Set talkativeness to 0 to ensure only mentions activate
    @ai_character.update!(talkativeness_factor: 0)
    alice.update!(talkativeness_factor: 0)
    alicex.update!(talkativeness_factor: 0)

    # Message mentions "Alice" (whole word)
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hey Alice, what do you think?"
    )

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

    assert_equal alice, speaker, "Should match 'Alice' exactly, not 'Alicex'"
  end

  test "natural splits multi-word names and matches individual words" do
    # Create a character with a multi-word name
    misaka_char = Character.create!(
      name: "Misaka Mikoto",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Misaka Mikoto", "description" => "Test" }
    )
    misaka = @space.space_memberships.create!(kind: "character", role: "member", character: misaka_char, position: 2)

    # Set talkativeness to 0 to ensure only mentions activate
    @ai_character.update!(talkativeness_factor: 0)
    misaka.update!(talkativeness_factor: 0)

    # Message mentions only "Mikoto" (second word of the name)
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Mikoto, can you explain that?"
    )

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

    assert_equal misaka, speaker, "Should match 'Mikoto' as part of 'Misaka Mikoto'"
  end

  test "natural matches first word of multi-word name" do
    # Create a character with a multi-word name
    misaka_char = Character.create!(
      name: "Misaka Mikoto",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Misaka Mikoto", "description" => "Test" }
    )
    misaka = @space.space_memberships.create!(kind: "character", role: "member", character: misaka_char, position: 2)

    # Set talkativeness to 0 to ensure only mentions activate
    @ai_character.update!(talkativeness_factor: 0)
    misaka.update!(talkativeness_factor: 0)

    # Message mentions only "Misaka" (first word of the name)
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hey Misaka, what's your opinion?"
    )

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

    assert_equal misaka, speaker, "Should match 'Misaka' as part of 'Misaka Mikoto'"
  end

  # ──────────────────────────────────────────────────────────────────
  # Assistant message mention detection tests
  # ──────────────────────────────────────────────────────────────────

  test "natural detects mentions from last assistant message" do
    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    # Set talkativeness to 0 to ensure only mentions activate
    @ai_character.update!(talkativeness_factor: 0)
    char_b.update!(talkativeness_factor: 0)

    # User message without mention
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello everyone!"
    )

    # Assistant message mentions char_b
    @conversation.messages.create!(
      space_membership: @ai_character,
      role: "assistant",
      content: "Let me ask Ready V3 Character about that."
    )

    selector = SpeakerSelector.new(@conversation)
    # In auto-mode, the activation text comes from the last message (assistant)
    speaker = selector.select_for_auto_mode(previous_speaker: @ai_character)

    assert_equal char_b, speaker, "Should detect mention from last assistant message"
  end

  # ──────────────────────────────────────────────────────────────────
  # Talkativeness probability tests
  # ──────────────────────────────────────────────────────────────────

  test "natural talkativeness 1.0 always activates candidate" do
    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    # Set char_b to always activate (talkativeness = 1.0)
    char_b.update!(talkativeness_factor: 1.0)
    # Set @ai_character to never activate (talkativeness = 0)
    @ai_character.update!(talkativeness_factor: 0)

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!" # No mention
    )

    # Run multiple times to verify consistency
    10.times do
      selector = SpeakerSelector.new(@conversation.reload)
      speaker = selector.select_for_user_turn
      assert_equal char_b, speaker, "talkativeness=1.0 should always activate"
    end
  end

  test "natural talkativeness 0.0 never activates candidate via probability" do
    # Both characters have talkativeness = 0
    @ai_character.update!(talkativeness_factor: 0)

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!" # No mention
    )

    # With talkativeness=0 and no mentions, should fall back to round-robin
    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

    # Since only @ai_character exists and talkativeness=0, fallback to round-robin
    # which returns the first eligible candidate
    assert_equal @ai_character, speaker, "Should fall back to round-robin when no activation"
  end

  test "natural talkativeness affects selection probability with fixed seed" do
    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    # Set different talkativeness values
    @ai_character.update!(talkativeness_factor: 0.2) # 20% chance
    char_b.update!(talkativeness_factor: 0.8) # 80% chance

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!" # No mention
    )

    # Run many trials and count selections
    trials = 100
    counts = Hash.new(0)

    trials.times do
      selector = SpeakerSelector.new(@conversation.reload)
      speaker = selector.select_for_user_turn
      counts[speaker.id] += 1
    end

    # With 0.8 vs 0.2 talkativeness, char_b should be selected more often
    # This is a probabilistic test, so we use a loose threshold
    assert counts[char_b.id] > counts[@ai_character.id],
           "Higher talkativeness (#{char_b.talkativeness_factor}) should be selected more often than lower (#{@ai_character.talkativeness_factor})"
  end

  # ──────────────────────────────────────────────────────────────────
  # allow_self_responses tests
  # ──────────────────────────────────────────────────────────────────

  test "natural respects allow_self_responses=false and excludes previous speaker" do
    @space.update!(allow_self_responses: false)

    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    # Set both to high talkativeness so they would normally both activate
    @ai_character.update!(talkativeness_factor: 1.0)
    char_b.update!(talkativeness_factor: 1.0)

    @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello!")
    @conversation.messages.create!(space_membership: @ai_character, role: "assistant", content: "Hi there!")

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_auto_mode(previous_speaker: @ai_character)

    assert_equal char_b, speaker, "Should not select previous speaker when allow_self_responses=false"
    assert_not_equal @ai_character, speaker
  end

  test "natural excludes banned speaker from mentions when allow_self_responses=false" do
    @space.update!(allow_self_responses: false)

    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    # Set talkativeness to 0 to ensure only mentions would activate
    @ai_character.update!(talkativeness_factor: 0)
    char_b.update!(talkativeness_factor: 0)

    @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello!")
    # Assistant message mentions @ai_character (Ready V2 Character), but @ai_character is the previous speaker
    @conversation.messages.create!(
      space_membership: @ai_character,
      role: "assistant",
      content: "I, Ready V2 Character, would like to continue."
    )

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_auto_mode(previous_speaker: @ai_character)

    # @ai_character is banned (previous speaker), so even though mentioned, it should be excluded
    # char_b should be selected via round-robin fallback
    assert_equal char_b, speaker, "Should not select mentioned speaker if they are banned"
  end

  # ──────────────────────────────────────────────────────────────────
  # Talkativeness default value test
  # ──────────────────────────────────────────────────────────────────

  test "talkativeness_factor defaults to 0.5" do
    new_char = Character.create!(
      name: "New Character",
      status: "ready",
      spec_version: 2,
      data: { "name" => "New Character", "description" => "Test" }
    )
    new_membership = @space.space_memberships.create!(kind: "character", role: "member", character: new_char, position: 5)

    assert_equal 0.5, new_membership.talkativeness_factor.to_f
  end
end
