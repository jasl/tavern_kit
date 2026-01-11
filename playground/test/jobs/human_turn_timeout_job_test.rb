# frozen_string_literal: true

require "test_helper"

class HumanTurnTimeoutJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(
      name: "HumanTurnTimeout Test Space",
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
    @ai_character = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      position: 1
    )

    ConversationRun.where(conversation: @conversation).delete_all

    # Enable auto mode
    @conversation.start_auto_mode!(rounds: 3)

    # Set up human turn
    @round_id = SecureRandom.uuid
    @conversation.update!(
      scheduling_state: "human_waiting",
      current_round_id: @round_id,
      current_speaker_id: @user_membership.id,
      round_position: 0,
      round_spoken_ids: [],
      round_queue_ids: [@user_membership.id, @ai_character.id]
    )

    @human_run = ConversationRun.create!(
      conversation: @conversation,
      status: "queued",
      kind: "human_turn",
      reason: "human_turn",
      speaker_space_membership_id: @user_membership.id,
      debug: { "round_id" => @round_id }
    )
  end

  test "skips human turn when timeout expires" do
    HumanTurnTimeoutJob.perform_now(@human_run.id, @round_id)

    @human_run.reload
    assert_equal "skipped", @human_run.status
    assert_equal "timeout", @human_run.debug["skipped_reason"]
  end

  test "advances scheduler after skip" do
    HumanTurnTimeoutJob.perform_now(@human_run.id, @round_id)

    @conversation.reload
    assert_equal @ai_character.id, @conversation.current_speaker_id
  end

  test "does nothing if run already succeeded" do
    @human_run.update!(status: "succeeded", finished_at: Time.current)

    HumanTurnTimeoutJob.perform_now(@human_run.id, @round_id)

    @human_run.reload
    assert_equal "succeeded", @human_run.status
    assert_equal @user_membership.id, @conversation.reload.current_speaker_id
  end

  test "does nothing if run already skipped" do
    @human_run.update!(status: "skipped", finished_at: Time.current)

    HumanTurnTimeoutJob.perform_now(@human_run.id, @round_id)

    @human_run.reload
    assert_equal "skipped", @human_run.status
  end

  test "does nothing if auto mode disabled" do
    @conversation.stop_auto_mode!
    @conversation.update!(scheduling_state: "human_waiting")

    HumanTurnTimeoutJob.perform_now(@human_run.id, @round_id)

    @human_run.reload
    # Run should still be queued (job exits early)
    assert_equal "queued", @human_run.status
  end

  test "does nothing if round has changed" do
    @conversation.update!(current_round_id: "new-round-id")

    HumanTurnTimeoutJob.perform_now(@human_run.id, @round_id)

    @human_run.reload
    # With the fix in Phase A, the job now checks round_id INSIDE the lock
    # before marking the run as skipped. If round has changed, it exits early.
    assert_equal "queued", @human_run.status, "Run should remain queued when round has changed"
  end

  test "does nothing if run not found" do
    # Should not raise, should exit silently
    assert_nothing_raised do
      HumanTurnTimeoutJob.perform_now(999999, @round_id)
    end
  end

  test "does nothing for non-human_turn run" do
    @human_run.update!(kind: "auto_response")

    HumanTurnTimeoutJob.perform_now(@human_run.id, @round_id)

    @human_run.reload
    assert_equal "queued", @human_run.status
  end

  test "extracts round_id from run debug if not provided" do
    HumanTurnTimeoutJob.perform_now(@human_run.id, nil)

    @human_run.reload
    assert_equal "skipped", @human_run.status
  end

  test "handles concurrent human message before timeout" do
    # Simulate human responding before timeout
    @human_run.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "I responded in time!"
    )

    # Timeout job runs (stale)
    HumanTurnTimeoutJob.perform_now(@human_run.id, @round_id)

    # Should have no effect
    @human_run.reload
    assert_equal "succeeded", @human_run.status
  end

  test "completes without error and logs result" do
    # Just verify the job completes without error
    # Logging is internal implementation detail
    assert_nothing_raised do
      HumanTurnTimeoutJob.perform_now(@human_run.id, @round_id)
    end

    # Verify the run was processed
    @human_run.reload
    assert_equal "skipped", @human_run.status
  end

  test "re-raises errors after logging" do
    TurnScheduler.stubs(:skip_human_turn!).raises(StandardError, "Test error")

    assert_raises(StandardError) do
      HumanTurnTimeoutJob.perform_now(@human_run.id, @round_id)
    end
  end
end
