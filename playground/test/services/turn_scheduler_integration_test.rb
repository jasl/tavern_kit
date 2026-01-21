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

    state = TurnScheduler.state(@conversation.reload)
    assert_not state.idle?
    assert_equal [@ai_character1.id, @ai_character2.id], state.round_queue_ids

    # 2. First AI responds
    first_run = @conversation.conversation_runs.queued.first
    assert_equal @ai_character1.id, first_run.speaker_space_membership_id
    first_run.update!(status: "succeeded", finished_at: Time.current)

    @conversation.messages.create!(
      space_membership: @ai_character1,
      role: "assistant",
      content: "Hello from AI 1!",
      conversation_run_id: first_run.id
    )

    # 3. Second AI should be scheduled
    assert_equal @ai_character2.id, TurnScheduler.state(@conversation.reload).current_speaker_id

    second_run = @conversation.conversation_runs.queued.first
    assert_equal @ai_character2.id, second_run.speaker_space_membership_id
    second_run.update!(status: "succeeded", finished_at: Time.current)

    @conversation.messages.create!(
      space_membership: @ai_character2,
      role: "assistant",
      content: "Hello from AI 2!",
      conversation_run_id: second_run.id
    )

    # 4. Round should complete, back to idle
    assert TurnScheduler.state(@conversation.reload).idle?
  end

  test "auto without human continues for multiple rounds" do
    @conversation.start_auto_without_human!(rounds: 3)

    # Start first round
    TurnScheduler.start_round!(@conversation)

    initial_rounds = @conversation.auto_without_human_remaining_rounds
    round_count = 0

    # Complete 2 full rounds
    2.times do
      queue = TurnScheduler.state(@conversation.reload).round_queue_ids
      queue.each do |speaker_id|
        speaker = @space.space_memberships.find(speaker_id)
        run = @conversation.conversation_runs.queued.first
        next unless run

        run.update!(status: "succeeded", finished_at: Time.current)
        @conversation.messages.create!(
          space_membership: speaker,
          role: "assistant",
          content: "Response from #{speaker.display_name}",
          conversation_run_id: run.id
        )
      end
      round_count += 1
    end

    @conversation.reload
    assert_equal initial_rounds - 2, @conversation.auto_without_human_remaining_rounds
  end

  # ===========================================================================
  # Mode Switching
  # ===========================================================================

  test "enabling auto without human mid-conversation" do
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

    # Now enable auto without human
    @conversation.start_auto_without_human!(rounds: 2)
    assert @conversation.auto_without_human_enabled?

    # Manually trigger next round
    TurnScheduler.start_round!(@conversation)

    # Should have scheduled next speaker
    assert_not TurnScheduler.state(@conversation.reload).idle?
  end

  test "disabling auto without human cancels queued runs" do
    @conversation.start_auto_without_human!(rounds: 3)
    TurnScheduler.start_round!(@conversation)

    queued_run = @conversation.conversation_runs.queued.first
    assert_not_nil queued_run

    # Disable auto without human
    @conversation.stop_auto_without_human!
    TurnScheduler.stop!(@conversation)

    queued_run.reload
    assert_equal "canceled", queued_run.status
  end

  test "enabling auto mid-round does not affect current round" do
    # Start a round
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    original_queue = TurnScheduler.state(@conversation.reload).round_queue_ids.dup

    # Create a new character for auto persona (to avoid unique constraint)
    auto_char = Character.create!(
      name: "Auto Persona",
      personality: "Test",
      data: { "name" => "Auto Persona" },
      spec_version: 2,
      file_sha256: "auto_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )

    # Enable auto for user with new character
    @user_membership.update!(
      character: auto_char,
      auto: "auto",
      auto_remaining_steps: 3
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
    assert_equal original_queue, TurnScheduler.state(@conversation).round_queue_ids
  end

  # ===========================================================================
  # User Interruption
  # ===========================================================================

  test "user message during AI turn advances scheduler" do
    @space.update!(during_generation_user_input_policy: "queue")

    first = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "First message"
    ).call
    assert first.success?

    first_round_id = TurnScheduler.state(@conversation.reload).current_round_id
    assert_not_nil first_round_id

    # User sends another message (this advances the turn scheduler)
    second = Messages::Creator.new(
      conversation: @conversation,
      membership: @user_membership,
      content: "Actually, wait..."
    ).call

    assert second.success?
    second_round_id = TurnScheduler.state(@conversation.reload).current_round_id
    assert_not_nil second_round_id
    assert_not_equal first_round_id, second_round_id
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

    original_queue = TurnScheduler.state(@conversation.reload).round_queue_ids.dup
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
    assert TurnScheduler.state(@conversation.reload).idle?
  end

  test "adding member mid-round does not add to current queue" do
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    original_queue = TurnScheduler.state(@conversation.reload).round_queue_ids.dup

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
    current_queue = TurnScheduler.state(@conversation).round_queue_ids
    assert_equal original_queue, current_queue
    assert_not_includes current_queue, new_ai.id
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
        TurnScheduler::Commands::AdvanceTurn.execute(
          conversation: @conversation,
          speaker_membership: @ai_character1
        )
      end
    end

    threads.each(&:join)

    # Should not crash, state should be consistent
    state = TurnScheduler.state(@conversation.reload)
    assert state.round_position >= 0
    assert state.round_spoken_ids.is_a?(Array)
  end

  # ===========================================================================
  # State Recovery
  # ===========================================================================

  test "recovers from stuck ai_generating state" do
    round =
      ConversationRound.create!(
        conversation: @conversation,
        status: "active",
        scheduling_state: "ai_generating",
        current_position: 0
      )
    round.participants.create!(space_membership: @ai_character1, position: 0)

    # Create stale running run
    stale_run = ConversationRun.create!(
      conversation: @conversation,
      status: "running",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character1.id,
      started_at: 15.minutes.ago,
      heartbeat_at: 15.minutes.ago,
      conversation_round_id: round.id,
      debug: {
        "trigger" => "auto_response",
        "scheduled_by" => "turn_scheduler",
      }
    )

    assert stale_run.stale?

    # Force stop should work
    TurnScheduler.stop!(@conversation)

    assert TurnScheduler.state(@conversation.reload).idle?
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

    list_queue = TurnScheduler.state(@conversation.reload).round_queue_ids.dup

    # Change to pooled
    @space.update!(reply_order: "pooled")

    # Current round queue should not change
    assert_equal list_queue, TurnScheduler.state(@conversation.reload).round_queue_ids
  end
end
