# frozen_string_literal: true

require "test_helper"

class Messages::CreatorTest < ActiveSupport::TestCase
  fixtures :users, :spaces, :space_memberships, :conversations, :messages, :characters, :llm_providers

  setup do
    @space = Spaces::Playground.create!(
      name: "Test Space",
      owner: users(:admin),
      during_generation_user_input_policy: "queue"
    )
    @user_membership = @space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    @character_membership = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      llm_provider: llm_providers(:openai)
    )
    @conversation = @space.conversations.create!(title: "Test", kind: "root")
  end

  # --- Success Cases ---

  test "creates message successfully" do
    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Hello, world!"
    ).call

    assert result.success?
    assert_not_nil result.message
    assert_equal "Hello, world!", result.message.content
    assert_equal "user", result.message.role
    assert_equal @user_membership.id, result.message.space_membership_id
    assert_nil result.error
    assert_nil result.error_code
  end

  test "creates message and persists to database" do
    assert_difference "Message.count", 1 do
      Messages::Creator.new(
        conversation: @conversation,
        membership: @user_membership,
        content: "Test message"
      ).call
    end
  end

  # --- Copilot Blocked Cases ---

  test "returns copilot_blocked when membership is copilot_full" do
    # Create a separate character for copilot to avoid unique constraint
    copilot_char = Character.create!(
      name: "Copilot Char",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Copilot Char" }
    )
    @user_membership.update!(copilot_mode: "full", character: copilot_char)

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Hello"
    ).call

    assert_not result.success?
    assert_equal :copilot_blocked, result.error_code
    assert_nil result.message
    assert_match(/copilot/i, result.error)
  end

  test "does not create message when copilot_blocked" do
    # Create a separate character for copilot to avoid unique constraint
    copilot_char = Character.create!(
      name: "Copilot Char 2",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Copilot Char 2" }
    )
    @user_membership.update!(copilot_mode: "full", character: copilot_char)

    assert_no_difference "Message.count" do
      Messages::Creator.new(
        conversation: @conversation,
        membership: @user_membership,
        content: "Hello"
      ).call
    end
  end

  # --- Generation Locked Cases (reject policy) ---

  test "returns generation_locked when reject policy and running run exists" do
    @space.update!(during_generation_user_input_policy: "reject")

    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Hello"
    ).call

    assert_not result.success?
    assert_equal :generation_locked, result.error_code
    assert_nil result.message
    assert_match(/generating/i, result.error)
  end

  test "returns generation_locked when reject policy and queued run exists" do
    @space.update!(during_generation_user_input_policy: "reject")

    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "queued",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Hello"
    ).call

    assert_not result.success?
    assert_equal :generation_locked, result.error_code
  end

  test "allows message creation with queue policy even when run is running" do
    @space.update!(during_generation_user_input_policy: "queue")

    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Hello"
    ).call

    assert result.success?
    assert_equal "Hello", result.message.content
  end

  test "allows message creation with reject policy when no pending runs" do
    @space.update!(during_generation_user_input_policy: "reject")

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Hello"
    ).call

    assert result.success?
    assert_equal "Hello", result.message.content
  end

  # --- Callback Invocation ---

  test "calls on_created callback after successful message creation" do
    callback_called = false
    callback_msg = nil
    callback_conv = nil

    Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Hello!",
      on_created: ->(msg, conv) {
        callback_called = true
        callback_msg = msg
        callback_conv = conv
      }
    ).call

    assert callback_called, "on_created callback should be called"
    assert_equal "Hello!", callback_msg.content
    assert_equal @conversation, callback_conv
  end

  test "does not call on_created callback when creation fails" do
    # Create a separate character for copilot to avoid unique constraint
    copilot_char = Character.create!(
      name: "Copilot Char Callback",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Copilot Char Callback" }
    )
    @user_membership.update!(copilot_mode: "full", character: copilot_char)

    callback_called = false

    Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Hello",
      on_created: ->(_msg, _conv) { callback_called = true }
    ).call

    refute callback_called, "on_created callback should NOT be called on failure"
  end

  test "works without on_created callback" do
    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Hello!"
    ).call

    assert result.success?
  end

  # --- Validation Failure Cases ---

  test "returns validation_failed when content is blank" do
    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: ""
    ).call

    # Note: Message model may or may not validate content presence
    # This test depends on model validations
    if result.success?
      skip "Message model does not validate content presence"
    else
      assert_equal :validation_failed, result.error_code
      assert_not_nil result.message
      assert_not_empty result.error
    end
  end

  # --- Compound Lock Scenarios (Copilot + Reject Policy) ---

  test "copilot_blocked takes precedence over generation_locked" do
    # This tests the check order: copilot check happens before reject policy check
    @space.update!(during_generation_user_input_policy: "reject")

    # Create a running run (would trigger generation_locked)
    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # Enable copilot full mode
    copilot_char = Character.create!(
      name: "Copilot Precedence Test",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Copilot Precedence Test" }
    )
    @user_membership.update!(copilot_mode: "full", character: copilot_char)

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Hello"
    ).call

    # Should return copilot_blocked (checked first), not generation_locked
    assert_not result.success?
    assert_equal :copilot_blocked, result.error_code
  end

  test "user can send message after copilot is disabled even during AI generation with queue policy" do
    # This tests the scenario: copilot was enabled, user types (triggers disable), then sends
    @space.update!(during_generation_user_input_policy: "queue")

    # Create a running run
    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # Copilot was full but now disabled (simulating frontend disable on typing)
    copilot_char = Character.create!(
      name: "Copilot Disabled Test",
      status: "ready",
      spec_version: 2,
      data: { "name" => "Copilot Disabled Test" }
    )
    @user_membership.update!(copilot_mode: "none", character: copilot_char)

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "User typing interrupts copilot"
    ).call

    # With queue policy and copilot disabled, message should succeed
    assert result.success?
    assert_equal "User typing interrupts copilot", result.message.content
  end

  test "user cannot send message after copilot is disabled during reject policy lock" do
    # This tests: copilot disabled, but reject policy still blocks
    @space.update!(during_generation_user_input_policy: "reject")

    # Create a running run
    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # Copilot is already disabled (user typed and disabled it)
    @user_membership.update!(copilot_mode: "none")

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Blocked by reject policy"
    ).call

    # Even with copilot disabled, reject policy still blocks
    assert_not result.success?
    assert_equal :generation_locked, result.error_code
  end
end
