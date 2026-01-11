# frozen_string_literal: true

require "test_helper"

# Focused fence tests for mode switching + membership changes mid-round.
# These cover scenarios that are easy to break in a rewrite:
# - enabling/disabling auto-mode mid-round
# - switching from auto-mode to copilot (mutual exclusion at UX layer)
# - adding/removing members while a round is active
#
# NOTE: These tests intentionally use the existing TurnScheduler + controllers
# as the public contract. The event-sourced ConversationEngine rewrite must
# continue to satisfy these behaviors.
class TurnSchedulerModeSwitchingTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)

    @space =
      Spaces::Playground.create!(
        name: "Scheduler Mode Switching Fence",
        owner: @user,
        reply_order: "list",
        during_generation_user_input_policy: "queue",
        user_turn_debounce_ms: 0
      )

    @conversation = @space.conversations.create!(title: "Main")

    @human =
      @space.space_memberships.create!(
        kind: "human",
        role: "owner",
        user: @user,
        position: 0
      )

    @ai1 =
      @space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v2),
        position: 1
      )

    @ai2 =
      @space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v3),
        position: 2
      )

    ConversationRun.where(conversation: @conversation).delete_all
  end

  test "enabling auto mode mid-round causes next round to start automatically after round completes" do
    # User message starts a list round: [ai1, ai2]
    @conversation.messages.create!(
      space_membership: @human,
      role: "user",
      content: "Hello!"
    )

    run1 = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil run1
    assert_equal @ai1.id, run1.speaker_space_membership_id

    # Enable auto mode while the round is already active.
    @conversation.start_auto_mode!(rounds: 2)
    assert @conversation.reload.auto_mode_enabled?

    # Simulate ai1 responding (clears the single-slot queued run).
    run1.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai1,
      role: "assistant",
      content: "AI1 response",
      generation_status: "succeeded",
      conversation_run_id: run1.id
    )

    run2 = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil run2
    assert_equal @ai2.id, run2.speaker_space_membership_id

    # Simulate ai2 responding, completing the list round.
    run2.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai2,
      role: "assistant",
      content: "AI2 response",
      generation_status: "succeeded",
      conversation_run_id: run2.id
    )

    # Auto mode should start a new round immediately (AI-to-AI).
    @conversation.reload
    assert @conversation.auto_mode_enabled?
    assert_equal "ai_generating", @conversation.scheduling_state

    run3 = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil run3, "Expected a new queued run after round completion with auto mode enabled"
    assert_equal @ai1.id, run3.speaker_space_membership_id
  end

  test "disabling auto mode stops scheduling and cancels queued runs" do
    @conversation.start_auto_mode!(rounds: 3)

    # Start a new round immediately (AI-to-AI).
    TurnScheduler.start_round!(@conversation, skip_to_ai: true)
    run = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil run

    # Disable auto mode and stop scheduling (same flow as ConversationsController#toggle_auto_mode disable).
    @conversation.stop_auto_mode!
    TurnScheduler.stop!(@conversation)

    @conversation.reload
    assert_equal "idle", @conversation.scheduling_state
    assert_not @conversation.auto_mode_enabled?

    assert_equal "canceled", run.reload.status
  end

  test "adding a member mid-round does not change the current round queue, but affects the next round" do
    @conversation.start_auto_mode!(rounds: 2)

    # Start a list round: [ai1, ai2]
    @conversation.messages.create!(
      space_membership: @human,
      role: "user",
      content: "Kick off"
    )

    @conversation.reload
    assert_equal [@ai1.id, @ai2.id], @conversation.round_queue_ids

    run1 = @conversation.conversation_runs.queued.order(:created_at, :id).last
    run1.update!(status: "succeeded", finished_at: Time.current)

    # While the round is active, add a new AI character membership.
    character3 =
      Character.create!(
        name: "ModeSwitch AI3",
        personality: "Test",
        data: { "name" => "ModeSwitch AI3" },
        spec_version: 2,
        file_sha256: "modeswitch_ai3_#{SecureRandom.hex(8)}",
        status: "ready",
        visibility: "private"
      )

    ai3 =
      @space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: character3,
        position: 3
      )

    # The *current* round queue should not change (it's persisted).
    assert_equal [@ai1.id, @ai2.id], @conversation.reload.round_queue_ids

    # Finish ai1, schedule ai2.
    @conversation.messages.create!(
      space_membership: @ai1,
      role: "assistant",
      content: "AI1 response",
      generation_status: "succeeded",
      conversation_run_id: run1.id
    )

    run2 = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_equal @ai2.id, run2.speaker_space_membership_id

    # Finish ai2 to complete the round and trigger next round (auto mode).
    run2.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai2,
      role: "assistant",
      content: "AI2 response",
      generation_status: "succeeded",
      conversation_run_id: run2.id
    )

    # Next round should include the new member in list order.
    @conversation.reload
    assert_equal [@ai1.id, @ai2.id, ai3.id], @conversation.round_queue_ids
  end

  test "removing a member mid-round causes scheduler to skip them when advancing" do
    @conversation.start_auto_mode!(rounds: 2)

    # Start list round [ai1, ai2].
    @conversation.messages.create!(
      space_membership: @human,
      role: "user",
      content: "Kick off"
    )

    run1 = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_equal @ai1.id, run1.speaker_space_membership_id

    # Remove ai2 before we advance to them.
    @ai2.remove!(by_user: @user, reason: "test removal")
    @ai2.reload
    assert_equal "removed", @ai2.status, "ai2 should be removed"
    assert_equal "muted", @ai2.participation, "ai2 should be muted"

    # Finish ai1 — advancing should skip removed ai2 and complete the round.
    run1.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai1,
      role: "assistant",
      content: "AI1 response",
      generation_status: "succeeded",
      conversation_run_id: run1.id
    )

    @conversation.reload

    # With auto mode enabled, round completion should start a new round.
    assert_equal "ai_generating", @conversation.scheduling_state
    next_run = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil next_run
    assert_equal @ai1.id, next_run.speaker_space_membership_id
  end
end
