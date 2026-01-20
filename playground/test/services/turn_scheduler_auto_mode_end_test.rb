# frozen_string_literal: true

require "test_helper"

# Tests for Auto without human ending behavior.
#
# These tests verify that when Auto without human ends (remaining rounds reach 0),
# the conversation correctly transitions to idle state and the UI reflects
# the correct state without showing "idle_unexpected" errors.
#
class TurnSchedulerAutoModeEndTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(
      name: "Auto Mode End Test Space",
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
  # Auto without human end - state transitions
  # ===========================================================================

  test "auto without human ending transitions to idle state correctly" do
    # Start with 1 round of auto without human
    @conversation.start_auto_without_human!(rounds: 1)
    assert_equal 1, @conversation.auto_without_human_remaining_rounds

    # Start the round
    TurnScheduler.start_round!(@conversation)
    state = TurnScheduler.state(@conversation.reload)
    assert_not state.idle?
    assert_equal "ai_generating", state.scheduling_state

    # Complete first AI's turn
    run1 = @conversation.conversation_runs.queued.first
    run1.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai_character1,
      role: "assistant",
      content: "Response from AI 1",
      conversation_run_id: run1.id
    )

    # Second AI should be scheduled
    state = TurnScheduler.state(@conversation.reload)
    assert_not state.idle?
    assert_equal @ai_character2.id, state.current_speaker_id

    # Complete second AI's turn (this should end the round AND auto mode)
    run2 = @conversation.conversation_runs.queued.first
    run2.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai_character2,
      role: "assistant",
      content: "Response from AI 2",
      conversation_run_id: run2.id
    )

    # After the last message, auto without human should be disabled and state should be idle
    @conversation.reload
    assert_nil @conversation.auto_without_human_remaining_rounds
    assert_not @conversation.auto_without_human_enabled?

    state = TurnScheduler.state(@conversation)
    assert state.idle?
    assert_equal "idle", state.scheduling_state
  end

  test "health checker reports healthy (not idle_unexpected) after auto without human ends" do
    # Start with 1 round of auto without human
    @conversation.start_auto_without_human!(rounds: 1)
    TurnScheduler.start_round!(@conversation)

    # Complete all AI turns
    [@ai_character1, @ai_character2].each do |speaker|
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

    @conversation.reload

    # Health check should report healthy, not idle_unexpected
    health = Conversations::HealthChecker.check(@conversation)
    assert_equal "healthy", health[:status], "Expected healthy status after auto mode ends, got: #{health.inspect}"
  end

  test "group queue presenter shows idle state after auto without human ends" do
    # Start with 1 round of auto without human
    @conversation.start_auto_without_human!(rounds: 1)
    TurnScheduler.start_round!(@conversation)

    # Complete all AI turns
    [@ai_character1, @ai_character2].each do |speaker|
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

    @conversation.reload

    # Presenter should show idle state
    presenter = GroupQueuePresenter.new(conversation: @conversation, space: @space)
    assert presenter.idle?, "Expected presenter to report idle after auto mode ends"
    assert_equal "idle", presenter.scheduling_state
    assert_nil presenter.current_speaker
  end

  test "no active round exists after auto without human ends" do
    @conversation.start_auto_without_human!(rounds: 1)
    TurnScheduler.start_round!(@conversation)

    # Complete all AI turns
    [@ai_character1, @ai_character2].each do |speaker|
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

    @conversation.reload

    # No active round should exist
    active_round = @conversation.conversation_rounds.find_by(status: "active")
    assert_nil active_round, "Expected no active round after auto mode ends"

    # The last round should be finished
    last_round = @conversation.conversation_rounds.order(created_at: :desc).first
    assert_equal "finished", last_round.status
    assert_equal "round_complete", last_round.ended_reason
  end

  test "no queued or running runs exist after auto without human ends" do
    @conversation.start_auto_without_human!(rounds: 1)
    TurnScheduler.start_round!(@conversation)

    # Complete all AI turns
    [@ai_character1, @ai_character2].each do |speaker|
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

    @conversation.reload

    # No active runs should exist
    assert_equal 0, @conversation.conversation_runs.queued.count
    assert_equal 0, @conversation.conversation_runs.running.count
  end

  # ===========================================================================
  # Auto without human end - multiple rounds
  # ===========================================================================

  test "auto without human with multiple rounds decrements correctly and ends properly" do
    @conversation.start_auto_without_human!(rounds: 2)

    # First round
    TurnScheduler.start_round!(@conversation)
    [@ai_character1, @ai_character2].each do |speaker|
      run = @conversation.conversation_runs.queued.first
      next unless run

      run.update!(status: "succeeded", finished_at: Time.current)
      @conversation.messages.create!(
        space_membership: speaker,
        role: "assistant",
        content: "Round 1: #{speaker.display_name}",
        conversation_run_id: run.id
      )
    end

    @conversation.reload
    assert_equal 1, @conversation.auto_without_human_remaining_rounds
    assert_not TurnScheduler.state(@conversation).idle?

    # Second round (should start automatically)
    [@ai_character1, @ai_character2].each do |speaker|
      run = @conversation.conversation_runs.queued.first
      next unless run

      run.update!(status: "succeeded", finished_at: Time.current)
      @conversation.messages.create!(
        space_membership: speaker,
        role: "assistant",
        content: "Round 2: #{speaker.display_name}",
        conversation_run_id: run.id
      )
    end

    @conversation.reload
    assert_nil @conversation.auto_without_human_remaining_rounds
    assert TurnScheduler.state(@conversation).idle?

    health = Conversations::HealthChecker.check(@conversation)
    assert_equal "healthy", health[:status]
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  test "auto without human ending with single AI character" do
    # Remove second AI (soft removal)
    @ai_character2.remove!

    @conversation.start_auto_without_human!(rounds: 1)
    TurnScheduler.start_round!(@conversation)

    run = @conversation.conversation_runs.queued.first
    run.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai_character1,
      role: "assistant",
      content: "Solo response",
      conversation_run_id: run.id
    )

    @conversation.reload
    assert_nil @conversation.auto_without_human_remaining_rounds
    assert TurnScheduler.state(@conversation).idle?

    health = Conversations::HealthChecker.check(@conversation)
    assert_equal "healthy", health[:status]
  end

  test "broadcast is sent with correct idle state after auto without human ends" do
    @conversation.start_auto_without_human!(rounds: 1)
    TurnScheduler.start_round!(@conversation)

    # Complete all AI turns
    [@ai_character1, @ai_character2].each do |speaker|
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

    @conversation.reload

    # Verify the presenter shows correct state (which is what the broadcast uses)
    presenter = GroupQueuePresenter.new(conversation: @conversation, space: @space)
    assert_equal "idle", presenter.scheduling_state,
                 "Expected presenter to have idle scheduling_state after auto without human ends"
  end

  # ===========================================================================
  # Health Check Timing Scenarios
  # ===========================================================================

  test "health check during auto without human last round shows healthy after completion" do
    @conversation.start_auto_without_human!(rounds: 1)
    TurnScheduler.start_round!(@conversation)

    # Complete first AI
    run1 = @conversation.conversation_runs.queued.first
    run1.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai_character1,
      role: "assistant",
      content: "Response 1",
      conversation_run_id: run1.id
    )

    # Health check during the round should show healthy (AI is generating)
    health_mid_round = Conversations::HealthChecker.check(@conversation.reload)
    assert_equal "healthy", health_mid_round[:status]

    # Complete second AI (this ends auto mode)
    run2 = @conversation.conversation_runs.queued.first
    run2.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai_character2,
      role: "assistant",
      content: "Response 2",
      conversation_run_id: run2.id
    )

    # Health check after auto mode ends should show healthy
    @conversation.reload
    health_after = Conversations::HealthChecker.check(@conversation)
    assert_equal "healthy", health_after[:status],
                 "Expected healthy after auto without human ends. Last message: #{@conversation.messages.last&.role}, " \
                 "auto_without_human_enabled: #{@conversation.auto_without_human_enabled?}, " \
                 "scheduler_state: #{TurnScheduler.state(@conversation).scheduling_state}"
  end

  test "health check with stale conversation instance still returns correct status" do
    @conversation.start_auto_without_human!(rounds: 1)
    TurnScheduler.start_round!(@conversation)

    # Keep a stale reference to the conversation
    stale_conversation = Conversation.find(@conversation.id)

    # Complete all AI turns
    [@ai_character1, @ai_character2].each do |speaker|
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

    # Health check with stale instance should still work correctly
    # because HealthChecker queries the database
    health = Conversations::HealthChecker.check(stale_conversation)
    assert_equal "healthy", health[:status]
  end

  # ===========================================================================
  # Race Condition Scenarios
  # ===========================================================================

  test "concurrent message creation during auto mode end does not cause stuck state" do
    @conversation.start_auto_without_human!(rounds: 1)
    TurnScheduler.start_round!(@conversation)

    # Complete first AI
    run1 = @conversation.conversation_runs.queued.first
    run1.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai_character1,
      role: "assistant",
      content: "Response 1",
      conversation_run_id: run1.id
    )

    # Complete second AI (this triggers auto mode end)
    run2 = @conversation.conversation_runs.queued.first
    run2.update!(status: "succeeded", finished_at: Time.current)

    # Simulate concurrent access by creating multiple threads
    threads = 3.times.map do
      Thread.new do
        @conversation.messages.create!(
          space_membership: @ai_character2,
          role: "assistant",
          content: "Concurrent response #{Thread.current.object_id}",
          conversation_run_id: run2.id
        )
      rescue ActiveRecord::RecordNotUnique
        # Expected for duplicate seq
      end
    end

    threads.each(&:join)

    @conversation.reload
    state = TurnScheduler.state(@conversation)

    # State should be consistent - either idle or in a valid active state
    if state.idle?
      health = Conversations::HealthChecker.check(@conversation)
      assert_equal "healthy", health[:status]
    else
      # If not idle, should have a valid active round
      assert_not_nil state.current_round_id
    end
  end
end
