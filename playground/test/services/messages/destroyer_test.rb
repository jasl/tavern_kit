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

  test "cancels queued turn_scheduler run when deleting the tail message" do
    # Clear any auto-created runs from message callbacks
    ConversationRun.where(conversation: @conversation).destroy_all

    queued_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "queued",
      reason: "test",
      debug: { "trigger" => "auto_response", "scheduled_by" => "turn_scheduler" }
    )

    Messages::Destroyer.new(message: @message, conversation: @conversation).call

    queued_run.reload
    assert_equal "canceled", queued_run.status
  end

  test "does not cancel unrelated queued runs (e.g., force_talk) when deleting the tail message" do
    # Clear any auto-created runs from message callbacks
    ConversationRun.where(conversation: @conversation).destroy_all

    queued_run = ConversationRun.create!(
      kind: "force_talk",
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "queued",
      reason: "test",
      debug: { "trigger" => "force_talk" }
    )

    Messages::Destroyer.new(message: @message, conversation: @conversation).call

    queued_run.reload
    assert_equal "queued", queued_run.status
  end

  test "requests cancellation for a running turn_scheduler run when deleting the tail message" do
    # Clear any auto-created runs from message callbacks
    ConversationRun.where(conversation: @conversation).destroy_all

    running_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "running",
      reason: "test",
      debug: { "trigger" => "auto_response", "scheduled_by" => "turn_scheduler" }
    )

    Messages::Destroyer.new(message: @message, conversation: @conversation).call

    running_run.reload
    assert running_run.cancel_requested_at.present?, "Expected cancel_requested_at to be set"
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
