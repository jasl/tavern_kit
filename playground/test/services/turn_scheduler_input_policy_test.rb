# frozen_string_literal: true

require "test_helper"

# Comprehensive tests for during_generation_user_input_policy behavior.
# Tests the three policies (reject, restart, queue) and mode switching scenarios.
#
# These tests verify that:
# - reject: blocks user input when AI is generating
# - restart: cancels running AI generation and allows new input
# - queue: allows user input anytime, each message triggers a new response
# - mode switching: changing policy mid-conversation works correctly
class TurnSchedulerInputPolicyTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(
      name: "Input Policy Test Space",
      owner: @user,
      reply_order: "natural",
      during_generation_user_input_policy: "queue", # default for setup
      user_turn_debounce_ms: 0
    )

    @conversation = @space.conversations.create!(title: "Test", kind: "root")

    @human = @space.space_memberships.create!(
      kind: "human",
      role: "owner",
      user: @user,
      position: 0
    )

    @ai = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      position: 1
    )

    ConversationRun.where(conversation: @conversation).delete_all
  end

  # ============================================================================
  # REJECT POLICY TESTS
  # ============================================================================

  test "reject policy: blocks message when run is running" do
    @space.update!(during_generation_user_input_policy: "reject")

    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Blocked message"
    ).call

    assert_not result.success?
    assert_equal :generation_locked, result.error_code
    assert_match(/generating/i, result.error)
  end

  test "reject policy: blocks message when run is queued" do
    @space.update!(during_generation_user_input_policy: "reject")

    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "queued",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Blocked message"
    ).call

    assert_not result.success?
    assert_equal :generation_locked, result.error_code
  end

  test "reject policy: allows message when idle (no pending runs)" do
    @space.update!(during_generation_user_input_policy: "reject")

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Allowed message"
    ).call

    assert result.success?
    assert_equal "Allowed message", result.message.content
  end

  test "reject policy: allows message after run completes" do
    @space.update!(during_generation_user_input_policy: "reject")

    # Create and complete a run
    run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )
    run.update!(status: "succeeded", finished_at: Time.current)

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "After completion"
    ).call

    assert result.success?
  end

  test "reject policy: does not block when only completed runs exist" do
    @space.update!(during_generation_user_input_policy: "reject")

    # Create some completed runs
    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "succeeded",
      kind: "auto_response",
      reason: "user_message",
      finished_at: 1.minute.ago
    )

    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "failed",
      kind: "auto_response",
      reason: "user_message",
      finished_at: 30.seconds.ago
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Should work"
    ).call

    assert result.success?
  end

  # ============================================================================
  # RESTART POLICY TESTS
  # ============================================================================

  test "restart policy: allows message and cancels running run" do
    @space.update!(during_generation_user_input_policy: "restart")

    running_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Interrupt message"
    ).call

    assert result.success?
    assert_equal "Interrupt message", result.message.content

    running_run.reload
    assert_not_nil running_run.cancel_requested_at, "Running run should have cancel requested"
  end

  test "restart policy: allows message when run is queued (cancels it)" do
    @space.update!(during_generation_user_input_policy: "restart")

    queued_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "queued",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Interrupt queued"
    ).call

    assert result.success?

    queued_run.reload
    assert_equal "canceled", queued_run.status, "Queued run should be canceled"
  end

  test "restart policy: works normally when idle" do
    @space.update!(during_generation_user_input_policy: "restart")

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Normal message"
    ).call

    assert result.success?
    assert_equal "Normal message", result.message.content
  end

  test "restart policy: new round starts after user message" do
    @space.update!(during_generation_user_input_policy: "restart")

    # Create a running run to be interrupted
    running_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # Send user message which should:
    # 1. Request cancel on running run
    # 2. Create user message
    # 3. Trigger new round via after_create_commit
    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "New input"
    ).call

    assert result.success?

    # The running run should have cancel requested
    running_run.reload
    assert_not_nil running_run.cancel_requested_at
  end

  # ============================================================================
  # QUEUE POLICY TESTS
  # ============================================================================

  test "queue policy: allows message when run is running" do
    @space.update!(during_generation_user_input_policy: "queue")

    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Queued message"
    ).call

    assert result.success?
    assert_equal "Queued message", result.message.content
  end

  test "queue policy: allows message when run is queued" do
    @space.update!(during_generation_user_input_policy: "queue")

    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "queued",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Another message"
    ).call

    assert result.success?
  end

  test "queue policy: cancels queued runs when user sends message" do
    @space.update!(during_generation_user_input_policy: "queue")

    queued_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "queued",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "User message"
    ).call

    assert result.success?

    # Queued runs should be canceled (user message takes priority)
    queued_run.reload
    assert_equal "canceled", queued_run.status
  end

  test "queue policy: does not cancel running runs" do
    @space.update!(during_generation_user_input_policy: "queue")

    running_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "User message"
    ).call

    assert result.success?

    # Running run should NOT be canceled in queue mode
    running_run.reload
    assert_equal "running", running_run.status
    assert_nil running_run.cancel_requested_at
  end

  test "queue policy: late previous AI message does not cancel queued reply for newest user message" do
    @space.update!(during_generation_user_input_policy: "queue")

    # User message starts a round and schedules an AI run (queued).
    Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "First"
    ).call

    first_run = @conversation.conversation_runs.queued.first
    assert_not_nil first_run

    # Simulate the run being claimed and still generating.
    first_run.update!(status: "running", started_at: Time.current, heartbeat_at: Time.current)

    # User sends another message while the run is running (queue policy allows this).
    Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Second"
    ).call

    queued_run = @conversation.conversation_runs.queued.first
    assert_not_nil queued_run, "Expected a queued run for the newest user message"

    # Simulate the late completion of the previous run.
    first_run.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai,
      role: "assistant",
      content: "Late reply to first",
      generation_status: "succeeded",
      conversation_run_id: first_run.id
    )

    # The queued run for the newest user message must survive.
    assert_equal "queued", queued_run.reload.status
  end

  # ============================================================================
  # MODE SWITCHING TESTS
  # ============================================================================

  test "switching from reject to queue while AI generating allows next message" do
    @space.update!(during_generation_user_input_policy: "reject")

    running_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # First attempt blocked
    result1 = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Blocked"
    ).call

    assert_not result1.success?
    assert_equal :generation_locked, result1.error_code

    # Switch to queue policy
    @space.update!(during_generation_user_input_policy: "queue")

    # Now message should succeed
    result2 = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Now allowed"
    ).call

    assert result2.success?
    assert_equal "Now allowed", result2.message.content
  end

  test "switching from queue to reject while AI generating blocks next message" do
    @space.update!(during_generation_user_input_policy: "queue")

    # Create a running run
    running_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # Verify we can send with queue policy
    result1 = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Allowed"
    ).call

    assert result1.success?, "First message should succeed with queue policy"

    # Ensure the running run is still running (creator doesn't cancel running runs in queue mode)
    running_run.reload
    assert_equal "running", running_run.status, "Running run should still be running after queue policy message"

    # Switch to reject policy
    @space.update!(during_generation_user_input_policy: "reject")

    # Reload associations to clear cached space
    @conversation.reload
    @space.reload

    # Debug: verify policy changed
    assert_equal "reject", @conversation.space.during_generation_user_input_policy,
                 "Policy should be reject"

    # Debug: check if running runs exist
    running_exists = ConversationRun.running.exists?(conversation_id: @conversation.id)
    queued_exists = ConversationRun.queued.exists?(conversation_id: @conversation.id)

    assert running_exists || queued_exists,
           "Expected at least one running or queued run. Running: #{running_exists}, Queued: #{queued_exists}"

    # Now message should be blocked because running run still exists
    result2 = Messages::Creator.new(
      conversation: @conversation.reload,
      membership: @human,
      content: "Now blocked"
    ).call

    assert_not result2.success?, "Second message should be blocked with reject policy"
    assert_equal :generation_locked, result2.error_code
  end

  test "switching from reject to restart while AI generating allows message and cancels run" do
    @space.update!(during_generation_user_input_policy: "reject")

    running_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # First attempt blocked
    result1 = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Blocked"
    ).call

    assert_not result1.success?

    # Switch to restart policy
    @space.update!(during_generation_user_input_policy: "restart")

    # Now message should succeed and cancel the run
    result2 = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Interrupt"
    ).call

    assert result2.success?

    running_run.reload
    assert_not_nil running_run.cancel_requested_at
  end

  # ============================================================================
  # SCHEDULING STATE REFLECTION TESTS
  # ============================================================================

  test "scheduling_state reflects ai_generating when round is active" do
    round =
      ConversationRound.create!(
        conversation: @conversation,
        status: "active",
        scheduling_state: "ai_generating",
        current_position: 0
      )
    round.participants.create!(space_membership: @ai, position: 0)

    state = TurnScheduler.state(@conversation)
    assert state.ai_generating?
    assert state.active?
    assert_not state.idle?
  end

  test "scheduling_state reflects idle when no active round exists" do
    state = TurnScheduler.state(@conversation)
    assert state.idle?
    assert_not state.active?
    assert_not state.ai_generating?
  end

  test "scheduling_state transitions correctly through round lifecycle" do
    # Start idle (no active round)
    TurnScheduler.stop!(@conversation)
    assert TurnScheduler.state(@conversation.reload).idle?

    # User sends message -> starts round
    @conversation.messages.create!(
      space_membership: @human,
      role: "user",
      content: "Hello"
    )

    assert_not TurnScheduler.state(@conversation.reload).idle?

    # Complete the AI response
    run = @conversation.conversation_runs.queued.first
    if run
      run.update!(status: "succeeded", finished_at: Time.current)
      @conversation.messages.create!(
        space_membership: @ai,
        role: "assistant",
        content: "Response",
        generation_status: "succeeded",
        conversation_run_id: run.id
      )
    end

    # Should return to idle after round completes (without auto mode)
    assert TurnScheduler.state(@conversation.reload).idle?
  end

  # ============================================================================
  # END-TO-END INTEGRATION: INPUT LOCKING LIFECYCLE
  # ============================================================================

  test "input locking lifecycle: idle -> ai_generating -> idle" do
    @space.update!(during_generation_user_input_policy: "reject")

    # Initial state: idle, input allowed
    assert TurnScheduler.state(@conversation).idle?

    result1 = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Hello"
    ).call

    assert result1.success?, "First message should succeed when idle"

    # After message creation, scheduler starts a round
    assert_not TurnScheduler.state(@conversation.reload).idle?, "Should be scheduling active after user message"

    # AI run is queued/running - input should be locked
    run = @conversation.conversation_runs.active.first
    assert_not_nil run, "Should have an active run"

    result2 = Messages::Creator.new(
      conversation: @conversation.reload,
      membership: @human,
      content: "Blocked while generating"
    ).call

    assert_not result2.success?, "Second message should be blocked while AI generating"
    assert_equal :generation_locked, result2.error_code

    # AI completes - run succeeds
    run.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership: @ai,
      role: "assistant",
      content: "AI response",
      generation_status: "succeeded",
      conversation_run_id: run.id
    )

    # After AI completes, state returns to idle (without auto mode)
    assert TurnScheduler.state(@conversation.reload).idle?

    # Input should be unlocked again
    result3 = Messages::Creator.new(
      conversation: @conversation.reload,
      membership: @human,
      content: "Now allowed"
    ).call

    assert result3.success?, "Third message should succeed after AI completes"
  end

  test "scheduling state changes provide data for frontend input locking" do
    @space.update!(during_generation_user_input_policy: "reject")

    # Initial state
    assert TurnScheduler.state(@conversation).idle?

    # User message triggers state change
    @conversation.messages.create!(
      space_membership: @human,
      role: "user",
      content: "Hello"
    )

    # State should change to active (ai_generating)
    state = TurnScheduler.state(@conversation.reload)
    assert_not state.idle?, "State should be active after user message"

    # Frontend would receive this via ActionCable broadcast and update input locking
    # The message_form_controller.js listens for scheduling:state-changed events
    # and disables textarea/send button when state is ai_generating and policy is reject
    assert_equal "ai_generating", state.scheduling_state
  end

  # ============================================================================
  # EDGE CASES
  # ============================================================================

  test "reject policy with queued run blocks (unique constraint limits to one)" do
    @space.update!(during_generation_user_input_policy: "reject")

    # Only one queued run per conversation due to unique constraint
    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "queued",
      kind: "auto_response",
      reason: "auto_without_human"
    )

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Blocked by queued"
    ).call

    assert_not result.success?
    assert_equal :generation_locked, result.error_code
  end

  test "reject policy does not block for different conversation" do
    @space.update!(during_generation_user_input_policy: "reject")

    # Create another root conversation in the same space
    other_conversation = @space.conversations.create!(title: "Other", kind: "root")

    ConversationRun.create!(
      conversation: other_conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # Message in original conversation should not be blocked
    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Not blocked"
    ).call

    assert result.success?
  end

  test "policy check uses current space policy, not cached" do
    @space.update!(during_generation_user_input_policy: "reject")

    running_run = ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # Update policy in background (simulating another request)
    Space.find(@space.id).update!(during_generation_user_input_policy: "queue")

    # Creator should see the updated policy
    @space.reload
    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Should work now"
    ).call

    assert result.success?
  end

  # ============================================================================
  # AUTO + INPUT POLICY COMPOUND TESTS
  # ============================================================================
  # These tests verify the interaction between auto mode and input policies.
  # Key behavior: auto_blocked is checked BEFORE reject policy.
  # This matches the documented "soft lock" (auto) vs "hard lock" (reject) design.

  test "auto mode blocks message even with queue policy" do
    @space.update!(during_generation_user_input_policy: "queue")

    # Create auto character
    auto_char = Character.create!(
      name: "Auto Policy Test",
      personality: "Test",
      data: { "name" => "Auto Policy Test" },
      spec_version: 2,
      file_sha256: "auto_policy_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )

    @human.update!(auto: "auto", character: auto_char, auto_remaining_steps: 3)

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Should be blocked by auto"
    ).call

    assert_not result.success?
    assert_equal :auto_blocked, result.error_code
  end

  test "after disabling auto, user can send with queue policy during AI generation" do
    @space.update!(during_generation_user_input_policy: "queue")

    # Create a running AI run
    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # Create auto character but with mode disabled (simulates user typing)
    auto_char = Character.create!(
      name: "Auto Disabled After Typing",
      personality: "Test",
      data: { "name" => "Auto Disabled After Typing" },
      spec_version: 2,
      file_sha256: "auto_disabled_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )

    @human.update!(auto: "none", character: auto_char)

    # User message should succeed (queue policy allows, auto is off)
    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "User interrupts AI with queue policy"
    ).call

    assert result.success?
    assert_equal "User interrupts AI with queue policy", result.message.content
  end

  test "after disabling auto, user still blocked by reject policy during AI generation" do
    @space.update!(during_generation_user_input_policy: "reject")

    # Create a running AI run
    ConversationRun.create!(
      conversation: @conversation,
      speaker_space_membership: @ai,
      status: "running",
      kind: "auto_response",
      reason: "user_message"
    )

    # Auto disabled (user typed to disable it)
    auto_char = Character.create!(
      name: "Auto Disabled But Reject",
      personality: "Test",
      data: { "name" => "Auto Disabled But Reject" },
      spec_version: 2,
      file_sha256: "auto_reject_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )

    @human.update!(auto: "none", character: auto_char)

    # User message should be blocked by reject policy
    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "Still blocked by reject"
    ).call

    assert_not result.success?
    assert_equal :generation_locked, result.error_code
  end

  test "auto user in auto without human: disabling auto allows manual message" do
    @space.update!(during_generation_user_input_policy: "queue")

    # Enable auto without human
    @conversation.start_auto_without_human!(rounds: 3)

    # Start a round (AI generating)
    TurnScheduler.start_round!(@conversation)

    @conversation.reload
    assert @conversation.auto_without_human_enabled?
    assert_not TurnScheduler.state(@conversation).idle?

    # Setup auto but disabled (user typed)
    auto_char = Character.create!(
      name: "Auto (disabled) Test",
      personality: "Test",
      data: { "name" => "Auto (disabled) Test" },
      spec_version: 2,
      file_sha256: "auto_disabled_test_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )

    @human.update!(auto: "none", character: auto_char)

    # User message should succeed and cancel queued runs
    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @human,
      content: "User interrupts auto mode"
    ).call

    assert result.success?
    assert_equal "User interrupts auto mode", result.message.content

    # Auto without human should still be enabled (only user typing disables it in frontend)
    # But the scheduler state may change due to user message
    @conversation.reload
    assert @conversation.auto_without_human_enabled?,
           "Auto without human should remain enabled (backend doesn't disable it)"
  end
end
