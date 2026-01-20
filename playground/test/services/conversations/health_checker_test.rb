# frozen_string_literal: true

require "test_helper"

class Conversations::HealthCheckerTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
  end

  test "healthy when no runs and no auto scheduling expected" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    result = Conversations::HealthChecker.check(conversation)

    assert_equal "healthy", result[:status]
    assert_equal "none", result[:action]
  end

  test "reports stuck when running run has no heartbeat for too long" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    travel_to Time.current.change(usec: 0) do
      started_at = Time.current - (Conversations::HealthChecker::STUCK_THRESHOLD + 1.second)
      run = ConversationRun.create!(
        conversation: conversation,
        speaker_space_membership_id: speaker.id,
        kind: "auto_response",
        status: "running",
        reason: "test",
        started_at: started_at,
        heartbeat_at: started_at
      )

      result = Conversations::HealthChecker.check(conversation)

      assert_equal "stuck", result[:status]
      assert_equal "retry", result[:action]
      assert_equal run.id, result.dig(:details, :run_id)
    end
  end

  test "reports stuck when queued run has been waiting too long" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    travel_to Time.current.change(usec: 0) do
      run = ConversationRun.create!(
        conversation: conversation,
        speaker_space_membership_id: speaker.id,
        kind: "auto_response",
        status: "queued",
        reason: "test",
        created_at: Time.current - (Conversations::HealthChecker::STUCK_THRESHOLD + 1.second),
        updated_at: Time.current - (Conversations::HealthChecker::STUCK_THRESHOLD + 1.second)
      )

      result = Conversations::HealthChecker.check(conversation)

      assert_equal "stuck", result[:status]
      assert_equal "retry", result[:action]
      assert_equal run.id, result.dig(:details, :run_id)
    end
  end

  test "reports failed when a recent failed run exists" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    travel_to Time.current.change(usec: 0) do
      run = ConversationRun.create!(
        conversation: conversation,
        speaker_space_membership_id: speaker.id,
        kind: "auto_response",
        status: "failed",
        reason: "test",
        finished_at: Time.current - 10.seconds,
        error: { "code" => "test_error" }
      )

      result = Conversations::HealthChecker.check(conversation)

      assert_equal "failed", result[:status]
      assert_equal "retry", result[:action]
      assert_equal run.id, result.dig(:details, :run_id)
    end
  end

  test "reports failed when scheduler is in failed state (even if run is not recent)" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "failed", current_position: 0)
    round.participants.create!(space_membership: speaker, position: 0, status: "pending")

    travel_to Time.current.change(usec: 0) do
      run = ConversationRun.create!(
        conversation: conversation,
        speaker_space_membership_id: speaker.id,
        kind: "auto_response",
        status: "failed",
        reason: "test",
        finished_at: Time.current - 2.hours,
        error: { "code" => "test_error" }
      )

      result = Conversations::HealthChecker.check(conversation)

      assert_equal "failed", result[:status]
      assert_equal "retry", result[:action]
      assert_equal run.id, result.dig(:details, :run_id)
    end
  end

  test "reports idle_unexpected when auto without human enabled but no run exists" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")
    conversation.start_auto_without_human!(rounds: 2)

    result = Conversations::HealthChecker.check(conversation)

    assert_equal "idle_unexpected", result[:status]
    assert_equal "generate", result[:action]
    assert_equal speaker.id, result.dig(:details, :suggested_speaker_id)
  end

  test "healthy when scheduler is paused (even if auto without human is enabled)" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")
    conversation.start_auto_without_human!(rounds: 2)

    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "paused", current_position: 0)
    round.participants.create!(space_membership: speaker, position: 0, status: "pending")

    result = Conversations::HealthChecker.check(conversation)

    assert_equal "healthy", result[:status]
    assert_equal "none", result[:action]
  end

  test "repairs ai_generating state when no active run exists but current speaker already succeeded" do
    TurnScheduler::Broadcasts.stubs(:queue_updated)
    Message.any_instance.stubs(:notify_scheduler_turn_complete)

    space = Spaces::Playground.create!(name: "HealthChecker Repair Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)
    conversation = space.conversations.create!(title: "Main")

    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "ai_generating", current_position: 0)
    round.participants.create!(space_membership: speaker, position: 0, status: "pending")

    run = ConversationRun.create!(
      conversation: conversation,
      conversation_round_id: round.id,
      speaker_space_membership_id: speaker.id,
      kind: "auto_response",
      status: "succeeded",
      reason: "auto_response",
      finished_at: Time.current,
      debug: { scheduled_by: "turn_scheduler" }
    )

    conversation.messages.create!(
      space_membership: speaker,
      role: "assistant",
      content: "Hello",
      conversation_run: run,
      generation_status: "succeeded"
    )

    result = Conversations::HealthChecker.check(conversation)
    assert_equal "healthy", result[:status]

    conversation.reload
    assert_equal "idle", TurnScheduler.state(conversation).scheduling_state
    assert_nil conversation.conversation_rounds.find_by(status: "active")
  end
end
