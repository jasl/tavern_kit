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
    @ai_character.destroy!

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
    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hey Ready V3 Character, what do you think about this?"
    )

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

    assert_equal char_b, speaker
  end

  test "natural mention detection is case insensitive" do
    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "hey ready v3 character, what's up?"
    )

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

    assert_equal char_b, speaker
  end

  test "natural falls back to round-robin when no mention" do
    char_b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello everyone!")
    @conversation.messages.create!(space_membership: @ai_character, role: "assistant", content: "Hi there!")

    selector = SpeakerSelector.new(@conversation)
    speaker = selector.select_for_user_turn

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
end
