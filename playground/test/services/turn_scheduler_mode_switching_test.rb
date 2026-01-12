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
    assert_equal "ai_generating", TurnScheduler.state(@conversation).scheduling_state

    run3 = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil run3, "Expected a new queued run after round completion with auto mode enabled"
    assert_equal @ai1.id, run3.speaker_space_membership_id
  end

  test "disabling auto mode stops scheduling and cancels queued runs" do
    @conversation.start_auto_mode!(rounds: 3)

    # Start a new round immediately (AI-to-AI).
    TurnScheduler.start_round!(@conversation)
    run = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil run

    # Disable auto mode and stop scheduling (same flow as ConversationsController#toggle_auto_mode disable).
    @conversation.stop_auto_mode!
    TurnScheduler.stop!(@conversation)

    @conversation.reload
    assert TurnScheduler.state(@conversation).idle?
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

    assert_equal [@ai1.id, @ai2.id], TurnScheduler.state(@conversation.reload).round_queue_ids

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
    assert_equal [@ai1.id, @ai2.id], TurnScheduler.state(@conversation.reload).round_queue_ids

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
    assert_equal [@ai1.id, @ai2.id, ai3.id], TurnScheduler.state(@conversation.reload).round_queue_ids
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
    assert_equal "ai_generating", TurnScheduler.state(@conversation).scheduling_state
    next_run = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil next_run
    assert_equal @ai1.id, next_run.speaker_space_membership_id
  end

  # ============================================================================
  # Copilot + Auto Mode Boundary Tests
  # ============================================================================

  test "auto mode queue excludes copilot user when copilot is disabled before next round starts" do
    # This test verifies that when copilot is disabled, the human is excluded
    # from the NEXT round's queue (not the current round, which is already persisted).

    @conversation.start_auto_mode!(rounds: 3)

    # Start first round with only AI characters (no copilot yet)
    TurnScheduler.start_round!(@conversation)

    @conversation.reload
    first_round_queue = TurnScheduler.state(@conversation).round_queue_ids.dup

    # Human should NOT be in queue (no copilot enabled)
    assert_not_includes first_round_queue, @human.id

    # Complete the first round (AI characters only)
    first_round_queue.each do |speaker_id|
      run = @conversation.conversation_runs.queued.first
      break unless run

      run.update!(status: "succeeded", finished_at: Time.current)
      speaker = @space.space_memberships.find(speaker_id)
      @conversation.messages.create!(
        space_membership: speaker,
        role: "assistant",
        content: "Response from #{speaker.display_name}",
        generation_status: "succeeded",
        conversation_run_id: run.id
      )
    end

    @conversation.reload

    # Verify second round started (auto mode continues)
    assert_equal "ai_generating", TurnScheduler.state(@conversation).scheduling_state
    second_round_queue = TurnScheduler.state(@conversation).round_queue_ids.dup

    # Human still not in queue (no copilot)
    assert_not_includes second_round_queue, @human.id,
                        "Human should not be in queue when copilot is not enabled"
  end

  test "ActivatedQueue correctly filters out disabled copilot users" do
    # This is a unit test for the queue building logic

    # Create copilot character
    copilot_char = Character.create!(
      name: "Copilot Filter Test",
      personality: "Test",
      data: { "name" => "Copilot Filter Test" },
      spec_version: 2,
      file_sha256: "copilot_filter_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )

    # Enable copilot
    @human.update!(
      character: copilot_char,
      copilot_mode: "full",
      copilot_remaining_steps: 5
    )

    # Build queue with copilot enabled
    queue_with_copilot = TurnScheduler::Queries::ActivatedQueue.call(
      conversation: @conversation,
      is_user_input: false
    )

    assert_includes queue_with_copilot.map(&:id), @human.id,
                    "Human should be in queue when copilot is enabled"

    # Disable copilot
    @human.update!(copilot_mode: "none")

    # Build queue with copilot disabled
    queue_without_copilot = TurnScheduler::Queries::ActivatedQueue.call(
      conversation: @conversation,
      is_user_input: false
    )

    assert_not_includes queue_without_copilot.map(&:id), @human.id,
                        "Human should NOT be in queue when copilot is disabled"
  end
end
