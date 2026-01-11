# frozen_string_literal: true

require "test_helper"

# End-to-end integration tests for the TurnScheduler system.
#
# These tests verify complete flows through the scheduler,
# including edge cases around concurrency, mode switching,
# and member changes.
#
class TurnSchedulerIntegrationTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(
      name: "Integration Test Space",
      owner: @user,
      reply_order: "list"
    )
    @conversation = @space.conversations.create!(title: "Main")
    @user_membership = @space.space_memberships.create!(
      kind: "human",
      role: "owner",
      user: @user,
      position: 0
    )
    @ai_character1 = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      position: 1
    )
    @ai_character2 = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2
    )

    ConversationRun.where(conversation: @conversation).delete_all
  end

  # ===========================================================================
  # Complete Round Flow
  # ===========================================================================

  test "complete round flow with list order" do
    # 1. User sends message
    user_msg = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello everyone!"
    )

    @conversation.reload
    assert_not_equal "idle", @conversation.scheduling_state
    assert_equal [@ai_character1.id, @ai_character2.id], @conversation.round_queue_ids

    # 2. First AI responds
    first_run = @conversation.conversation_runs.queued.first
    assert_equal @ai_character1.id, first_run.speaker_space_membership_id
    first_run.update!(status: "succeeded", finished_at: Time.current)

    @conversation.messages.create!(
      space_membership: @ai_character1,
      role: "assistant",
      content: "Hello from AI 1!"
    )

    # 3. Second AI should be scheduled
    @conversation.reload
    assert_equal @ai_character2.id, @conversation.current_speaker_id

    second_run = @conversation.conversation_runs.queued.first
    assert_equal @ai_character2.id, second_run.speaker_space_membership_id
    second_run.update!(status: "succeeded", finished_at: Time.current)

    @conversation.messages.create!(
      space_membership: @ai_character2,
      role: "assistant",
      content: "Hello from AI 2!"
    )

    # 4. Round should complete, back to idle
    @conversation.reload
    assert_equal "idle", @conversation.scheduling_state
  end

  test "auto mode continues for multiple rounds" do
    @conversation.start_auto_mode!(rounds: 3)

    # Start first round
    TurnScheduler.start_round!(@conversation)

    initial_rounds = @conversation.auto_mode_remaining_rounds
    round_count = 0

    # Complete 2 full rounds
    2.times do
      queue = @conversation.reload.round_queue_ids
      queue.each do |speaker_id|
        speaker = @space.space_memberships.find(speaker_id)
        run = @conversation.conversation_runs.queued.first
        next unless run

        run.update!(status: "succeeded", finished_at: Time.current)
        @conversation.messages.create!(
          space_membership: speaker,
          role: "assistant",
          content: "Response from #{speaker.display_name}"
        )
      end
      round_count += 1
    end

    @conversation.reload
    assert_equal initial_rounds - 2, @conversation.auto_mode_remaining_rounds
  end

  # ===========================================================================
  # Mode Switching
  # ===========================================================================

  test "enabling auto mode mid-conversation" do
    # Start normal conversation
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    # Complete first response
    run = @conversation.conversation_runs.queued.first
    run&.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai_character1,
      role: "assistant",
      content: "Hi!"
    )

    # Now enable auto mode
    @conversation.start_auto_mode!(rounds: 2)
    assert @conversation.auto_mode_enabled?

    # Manually trigger next round
    TurnScheduler.start_round!(@conversation)

    # Should have scheduled next speaker
    @conversation.reload
    assert_not_equal "idle", @conversation.scheduling_state
  end

  test "disabling auto mode cancels queued runs" do
    @conversation.start_auto_mode!(rounds: 3)
    TurnScheduler.start_round!(@conversation)

    queued_run = @conversation.conversation_runs.queued.first
    assert_not_nil queued_run

    # Disable auto mode
    @conversation.stop_auto_mode!
    TurnScheduler.stop!(@conversation)

    queued_run.reload
    assert_equal "canceled", queued_run.status
  end

  test "enabling copilot mid-round does not affect current round" do
    # Start a round
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    original_queue = @conversation.reload.round_queue_ids.dup

    # Create a new character for copilot persona (to avoid unique constraint)
    copilot_char = Character.create!(
      name: "Copilot Persona",
      personality: "Test",
      data: { "name" => "Copilot Persona" },
      spec_version: 2,
      file_sha256: "copilot_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )

    # Enable copilot for user with new character
    @user_membership.update!(
      character: copilot_char,
      copilot_mode: "full",
      copilot_remaining_steps: 3
    )

    # Complete current run
    run = @conversation.conversation_runs.queued.first
    run&.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai_character1,
      role: "assistant",
      content: "Response"
    )

    # Queue should not have changed mid-round
    @conversation.reload
    assert_equal original_queue, @conversation.round_queue_ids
  end

  # ===========================================================================
  # User Interruption
  # ===========================================================================

  test "user message during AI turn advances scheduler" do
    # Start round
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "First message"
    )

    @conversation.reload
    first_round_id = @conversation.current_round_id
    assert_not_nil first_round_id

    # User sends another message (this advances the turn scheduler)
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Actually, wait..."
    )

    # The scheduler state may change depending on implementation
    # Document current behavior: user message triggers advance_turn
    @conversation.reload
    # State should be valid (not corrupted)
    assert TurnScheduler::STATES.include?(@conversation.scheduling_state)
  end

  # ===========================================================================
  # Member Changes Mid-Round
  # ===========================================================================

  test "muting member mid-round causes scheduler to skip them when advancing" do
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    original_queue = @conversation.reload.round_queue_ids.dup
    assert_equal [@ai_character1.id, @ai_character2.id], original_queue

    # Mute second AI mid-round
    @ai_character2.update!(participation: "muted")

    # Complete first AI turn
    run = @conversation.conversation_runs.queued.first
    run&.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai_character1,
      role: "assistant",
      content: "Response 1"
    )

    # When advancing, scheduler should skip muted ai2 and complete the round
    # Since auto-mode is not enabled, the round ends and state becomes idle
    @conversation.reload
    assert_equal "idle", @conversation.scheduling_state

    # Round queue is cleared when round completes without auto-scheduling
    assert_equal [], @conversation.round_queue_ids
  end

  test "adding member mid-round does not add to current queue" do
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    original_queue = @conversation.reload.round_queue_ids.dup

    # Add new AI member
    new_ai = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: Character.create!(
        name: "New AI",
        personality: "New",
        data: { "name" => "New AI" },
        spec_version: 2,
        file_sha256: "new_ai_#{SecureRandom.hex(8)}",
        status: "ready",
        visibility: "private"
      ),
      position: 3
    )

    # Queue should not include new member
    @conversation.reload
    assert_equal original_queue, @conversation.round_queue_ids
    assert_not_includes @conversation.round_queue_ids, new_ai.id
  end

  # ===========================================================================
  # Human Turn Timeout
  # ===========================================================================

  test "human turn timeout flow" do
    # Clear existing runs
    ConversationRun.where(conversation: @conversation).delete_all

    # Set up human in copilot mode that can be skipped
    @user_membership.update!(copilot_mode: "none")

    @conversation.start_auto_mode!(rounds: 2)

    # Manually set up human as current speaker in queue
    round_id = SecureRandom.uuid
    @conversation.update!(
      scheduling_state: "human_waiting",
      current_round_id: round_id,
      current_speaker_id: @user_membership.id,
      round_position: 0,
      round_spoken_ids: [],
      round_queue_ids: [@user_membership.id, @ai_character1.id]
    )

    human_run = ConversationRun.create!(
      conversation: @conversation,
      status: "queued",
      kind: "human_turn",
      reason: "human_turn",
      speaker_space_membership_id: @user_membership.id,
      debug: { "round_id" => round_id }
    )

    # Simulate timeout job
    TurnScheduler.skip_human_turn!(@conversation, @user_membership.id, round_id)

    human_run.reload
    assert_equal "skipped", human_run.status

    @conversation.reload
    assert_equal @ai_character1.id, @conversation.current_speaker_id
  end

  # ===========================================================================
  # Concurrent Access
  # ===========================================================================

  test "concurrent message creation is handled safely" do
    # This test verifies that the with_lock mechanism prevents race conditions
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    # Simulate concurrent updates by running advance_turn multiple times
    # In production, these would be from different processes
    threads = 3.times.map do
      Thread.new do
        TurnScheduler::Commands::AdvanceTurn.call(
          conversation: @conversation,
          speaker_membership: @ai_character1
        )
      end
    end

    threads.each(&:join)

    # Should not crash, state should be consistent
    @conversation.reload
    # Verify state is valid (not corrupted)
    assert @conversation.round_position >= 0
    assert @conversation.round_spoken_ids.is_a?(Array)
  end

  # ===========================================================================
  # State Recovery
  # ===========================================================================

  test "recovers from stuck ai_generating state" do
    # Set up stuck state
    @conversation.update!(
      scheduling_state: "ai_generating",
      current_round_id: SecureRandom.uuid,
      current_speaker_id: @ai_character1.id
    )

    # Create stale running run
    stale_run = ConversationRun.create!(
      conversation: @conversation,
      status: "running",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character1.id,
      started_at: 15.minutes.ago,
      heartbeat_at: 15.minutes.ago
    )

    assert stale_run.stale?

    # Force stop should work
    TurnScheduler.stop!(@conversation)

    @conversation.reload
    assert_equal "idle", @conversation.scheduling_state
  end

  # ===========================================================================
  # Force Talk
  # ===========================================================================

  test "force talk works during active round" do
    # Start normal round
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    # Force second AI to talk (overriding queue)
    run = Conversations::RunPlanner.plan_force_talk!(
      conversation: @conversation,
      speaker_space_membership_id: @ai_character2.id
    )

    assert_not_nil run
    assert_equal @ai_character2.id, run.speaker_space_membership_id
    assert_equal "force_talk", run.reason
  end

  # ===========================================================================
  # Reply Order Switching
  # ===========================================================================

  test "changing reply order affects next round only" do
    @space.update!(reply_order: "list")

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    list_queue = @conversation.reload.round_queue_ids.dup

    # Change to pooled
    @space.update!(reply_order: "pooled")

    # Current round queue should not change
    @conversation.reload
    assert_equal list_queue, @conversation.round_queue_ids
  end
end
