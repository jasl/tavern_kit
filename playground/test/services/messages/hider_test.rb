# frozen_string_literal: true

require "test_helper"

class Messages::HiderTest < ActiveSupport::TestCase
  fixtures :users, :spaces, :space_memberships, :conversations, :messages, :characters, :llm_providers

  setup do
    # Avoid scheduler side effects in service tests
    Message.any_instance.stubs(:notify_scheduler_turn_complete)

    @space = Spaces::Playground.create!(name: "Message Hide Test Space", owner: users(:admin))
    @user_membership = @space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    @character_membership = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      llm_provider: llm_providers(:openai)
    )
    @conversation = @space.conversations.create!(title: "Test", kind: "root")
  end

  test "hides a message in an idle conversation (non-rollback)" do
    msg = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello")

    assert msg.visibility_normal?

    assert_no_difference "Message.count" do
      result = Messages::Hider.new(message: msg, conversation: @conversation).call
      assert result.success?
    end

    msg.reload
    assert msg.visibility_hidden?
    assert_nil @conversation.messages.ui_visible.find_by(id: msg.id)
  end

  test "hides tail message and cancels downstream queued legacy user_message run" do
    msg = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello")

    queued_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "queued",
      reason: "user_message",
      debug: { "trigger" => "user_message", "user_message_id" => msg.id }
    )

    result = Messages::Hider.new(message: msg, conversation: @conversation).call
    assert result.success?

    msg.reload
    assert msg.visibility_hidden?

    queued_run.reload
    assert_equal "canceled", queued_run.status
  end

  test "hides message while a run is running and requests cancel (stop generate)" do
    msg = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello")

    running_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      speaker_space_membership: @character_membership,
      status: "running",
      reason: "test"
    )

    result = Messages::Hider.new(message: msg, conversation: @conversation).call
    assert result.success?

    running_run.reload
    assert running_run.cancel_requested_at.present?
  end

  test "hides trigger message and cancels active round + downstream turn_scheduler queued run" do
    trigger = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Trigger")
    tail = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Tail")

    round =
      ConversationRound.create!(
        conversation: @conversation,
        status: "active",
        scheduling_state: "ai_generating",
        current_position: 0,
        trigger_message: trigger
      )

    queued_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      conversation_round: round,
      speaker_space_membership: @character_membership,
      status: "queued",
      reason: "auto_response",
      debug: { "scheduled_by" => "turn_scheduler", "trigger" => "auto_response", "expected_last_message_id" => tail.id }
    )

    result = Messages::Hider.new(message: trigger, conversation: @conversation).call
    assert result.success?

    trigger.reload
    assert trigger.visibility_hidden?

    round.reload
    assert_equal "canceled", round.status

    queued_run.reload
    assert_equal "canceled", queued_run.status
  end

  test "hides non-tail message without canceling queued turn_scheduler run or active round" do
    to_hide = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Old")
    trigger = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Trigger")
    tail = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Tail")

    round =
      ConversationRound.create!(
        conversation: @conversation,
        status: "active",
        scheduling_state: "ai_generating",
        current_position: 0,
        trigger_message: trigger
      )

    queued_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      conversation_round: round,
      speaker_space_membership: @character_membership,
      status: "queued",
      reason: "auto_response",
      debug: { "scheduled_by" => "turn_scheduler", "expected_last_message_id" => tail.id }
    )

    result = Messages::Hider.new(message: to_hide, conversation: @conversation).call
    assert result.success?

    to_hide.reload
    assert to_hide.visibility_hidden?

    queued_run.reload
    assert_equal "queued", queued_run.status

    round.reload
    assert_equal "active", round.status
  end

  test "hides scheduler-visible tail and cancels queued turn_scheduler run + active round (scheduler becomes idle)" do
    trigger = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Trigger")
    tail = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Tail")

    round =
      ConversationRound.create!(
        conversation: @conversation,
        status: "active",
        scheduling_state: "ai_generating",
        current_position: 0,
        trigger_message: trigger
      )

    queued_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      conversation_round: round,
      speaker_space_membership: @character_membership,
      status: "queued",
      reason: "auto_response",
      debug: { "scheduled_by" => "turn_scheduler", "expected_last_message_id" => tail.id }
    )

    result = Messages::Hider.new(message: tail, conversation: @conversation).call
    assert result.success?

    tail.reload
    assert tail.visibility_hidden?

    queued_run.reload
    assert_equal "canceled", queued_run.status

    round.reload
    assert_equal "canceled", round.status

    assert TurnScheduler.state(@conversation.reload).idle?
  end

  test "hides non-tail/non-trigger message during an active round without canceling the round" do
    to_hide = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Old")
    trigger = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Trigger")

    round =
      ConversationRound.create!(
        conversation: @conversation,
        status: "active",
        scheduling_state: "ai_generating",
        current_position: 0,
        trigger_message: trigger
      )

    result = Messages::Hider.new(message: to_hide, conversation: @conversation).call
    assert result.success?

    to_hide.reload
    assert to_hide.visibility_hidden?

    round.reload
    assert_equal "active", round.status
  end

  test "hides trigger message during an active round (no run) and cancels the round" do
    trigger = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Trigger")

    round =
      ConversationRound.create!(
        conversation: @conversation,
        status: "active",
        scheduling_state: "ai_generating",
        current_position: 0,
        trigger_message: trigger
      )

    result = Messages::Hider.new(message: trigger, conversation: @conversation).call
    assert result.success?

    trigger.reload
    assert trigger.visibility_hidden?

    round.reload
    assert_equal "canceled", round.status

    assert TurnScheduler.state(@conversation.reload).idle?
  end

  test "hides trigger message while a run is running and cancels round + queued run (stop generate semantics)" do
    trigger = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Trigger")
    tail = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Tail")

    round =
      ConversationRound.create!(
        conversation: @conversation,
        status: "active",
        scheduling_state: "ai_generating",
        current_position: 0,
        trigger_message: trigger
      )

    running_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      conversation_round: round,
      speaker_space_membership: @character_membership,
      status: "running",
      reason: "auto_response",
      debug: { "scheduled_by" => "turn_scheduler" }
    )

    queued_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      conversation_round: round,
      speaker_space_membership: @character_membership,
      status: "queued",
      reason: "auto_response",
      debug: { "scheduled_by" => "turn_scheduler", "expected_last_message_id" => tail.id }
    )

    result = Messages::Hider.new(message: trigger, conversation: @conversation).call
    assert result.success?

    trigger.reload
    assert trigger.visibility_hidden?

    running_run.reload
    assert running_run.cancel_requested_at.present?

    queued_run.reload
    assert_equal "canceled", queued_run.status

    round.reload
    assert_equal "canceled", round.status

    assert TurnScheduler.state(@conversation.reload).idle?
  end

  test "does not hide fork point messages" do
    msg = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello")

    branch = @space.conversations.create!(
      title: "Branch",
      kind: "branch",
      forked_from_message: msg,
      parent_conversation: @conversation
    )

    result = Messages::Hider.new(message: msg, conversation: @conversation).call

    assert_not result.success?
    assert_equal :fork_point_protected, result.error_code

    msg.reload
    assert msg.visibility_normal?
  ensure
    branch&.destroy
  end
end
