# frozen_string_literal: true

require "test_helper"

class Messages::DestroyerTest < ActiveSupport::TestCase
  fixtures :users, :spaces, :space_memberships, :conversations, :messages, :characters, :llm_providers

  setup do
    @space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    @user_membership = @space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    @character_membership = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      llm_provider: llm_providers(:openai)
    )
    @conversation = @space.conversations.create!(title: "Test", kind: "root")

    @message = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello"
    )
  end

  # --- Basic Destruction ---

  test "destroys the message" do
    assert_difference "Message.count", -1 do
      Messages::Destroyer.new(message: @message, conversation: @conversation).call
    end
  end

  test "message is removed from database" do
    message_id = @message.id
    Messages::Destroyer.new(message: @message, conversation: @conversation).call

    assert_nil Message.find_by(id: message_id)
  end

  # --- Orphaned Run Cancellation ---

  test "cancels queued user_turn run triggered by deleted message" do
    queued_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "queued",
      kind: "user_turn",
      reason: "user_message",
      debug: {
        "trigger" => "user_message",
        "user_message_id" => @message.id,
      }
    )

    Messages::Destroyer.new(message: @message, conversation: @conversation).call

    queued_run.reload
    assert_equal "canceled", queued_run.status
  end

  test "does not cancel queued run if trigger is not user_message" do
    queued_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "queued",
      kind: "user_turn",
      reason: "regenerate",
      debug: {
        "trigger" => "regenerate",
        "target_message_id" => 999,
      }
    )

    Messages::Destroyer.new(message: @message, conversation: @conversation).call

    queued_run.reload
    assert_equal "queued", queued_run.status
  end

  test "does not cancel queued run if user_message_id does not match" do
    other_message = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Other message"
    )

    queued_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "queued",
      kind: "user_turn",
      reason: "user_message",
      debug: {
        "trigger" => "user_message",
        "user_message_id" => other_message.id,
      }
    )

    Messages::Destroyer.new(message: @message, conversation: @conversation).call

    queued_run.reload
    assert_equal "queued", queued_run.status
  end

  test "does not cancel queued run if kind is not user_turn" do
    queued_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "queued",
      kind: "force_talk",
      reason: "force_talk",
      debug: {
        "trigger" => "force_talk",
      }
    )

    Messages::Destroyer.new(message: @message, conversation: @conversation).call

    queued_run.reload
    assert_equal "queued", queued_run.status
  end

  test "does not affect running runs" do
    running_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "running",
      kind: "user_turn",
      reason: "user_message",
      debug: {
        "trigger" => "user_message",
        "user_message_id" => @message.id,
      }
    )

    Messages::Destroyer.new(message: @message, conversation: @conversation).call

    running_run.reload
    assert_equal "running", running_run.status
  end

  # --- Callback Invocation ---

  test "calls on_destroyed callback after successful destruction" do
    callback_called = false
    callback_msg = nil
    callback_conv = nil

    Messages::Destroyer.new(
      message: @message,
      conversation: @conversation,
      on_destroyed: ->(msg, conv) {
        callback_called = true
        callback_msg = msg
        callback_conv = conv
      }
    ).call

    assert callback_called, "on_destroyed callback should be called"
    assert_equal @message.id, callback_msg.id
    assert_equal @conversation, callback_conv
  end

  test "does not call on_destroyed callback when destruction fails" do
    # Create a branch from this message to make it a fork point
    branch = @space.conversations.create!(
      title: "Branch",
      kind: "branch",
      forked_from_message: @message,
      parent_conversation: @conversation
    )

    callback_called = false

    result = Messages::Destroyer.new(
      message: @message,
      conversation: @conversation,
      on_destroyed: ->(_msg, _conv) { callback_called = true }
    ).call

    refute callback_called, "on_destroyed callback should NOT be called on failure"
    assert_equal :fork_point_protected, result.error_code

    branch.destroy # cleanup
  end

  test "works without on_destroyed callback" do
    result = Messages::Destroyer.new(
      message: @message,
      conversation: @conversation
    ).call

    assert result.success?
  end
end
