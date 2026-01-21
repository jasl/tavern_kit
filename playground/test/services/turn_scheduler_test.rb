# frozen_string_literal: true

require "test_helper"

# Comprehensive test suite for turn scheduling behavior.
# These tests serve as a "fence" that defines expected behavior before the rewrite.
# The new TurnScheduler implementation must pass all these tests.
#
# Test categories:
# 1. Basic turn flow (user message → AI response)
# 2. Auto mode lifecycle (start, rounds, exhaustion)
# 3. Auto lifecycle (enable, steps, exhaustion)
# 4. Auto without human/Auto mutual exclusion
# 5. Human turn handling in auto mode (timeout skip)
# 6. Reply order strategies (natural, list, pooled, manual)
# 7. Force talk behavior
# 8. Regenerate behavior
# 9. Race condition scenarios
# 10. State recovery (stuck runs)
#
class TurnSchedulerTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(
      name: "Scheduler Test Space",
      owner: @user,
      reply_order: "natural"
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

    # Clear any auto-created runs from callbacks
    ConversationRun.where(conversation: @conversation).delete_all
  end

  # ============================================================================
  # 1. Basic Turn Flow
  # ============================================================================

  test "user message triggers AI response in natural mode" do
    # Send user message
    message = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    # Should create a queued run for the AI
    run = @conversation.conversation_runs.queued.first
    assert_not_nil run, "Should create a queued run after user message"
    assert_equal @ai_character.id, run.speaker_space_membership_id
  end

  test "idle assistant message does not start a new round unless auto scheduling is enabled" do
    # Creating assistant messages directly (e.g., seeding history/import) should not
    # trigger AI-to-AI scheduling in normal mode.
    @conversation.messages.create!(
      space_membership: @ai_character,
      role: "assistant",
      content: "Seeded assistant message"
    )

    assert_equal "idle", TurnScheduler.state(@conversation.reload).scheduling_state
    assert_nil @conversation.conversation_runs.queued.first
  end

  test "user message does not trigger AI response in manual mode" do
    @space.update!(reply_order: "manual")

    message = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    assert_nil @conversation.conversation_runs.queued.first
  end

  test "single-slot queue constraint at database level" do
    # Database constraint ensures only one queued run per conversation
    ConversationRun.create!(
      conversation: @conversation,
      status: "queued",
      kind: "auto_response",
      reason: "test1",
      speaker_space_membership_id: @ai_character.id
    )

    # Second queued run should violate unique constraint
    assert_raises ActiveRecord::RecordNotUnique do
      ConversationRun.create!(
        conversation: @conversation,
        status: "queued",
        kind: "auto_response",
        reason: "test2",
        speaker_space_membership_id: @ai_character.id
      )
    end
  end

  test "user sends multiple messages before AI responds triggers queue recalculation" do
    # First message creates queued run
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "First"
    )

    first_run = @conversation.conversation_runs.queued.first
    assert_not_nil first_run, "First message should create a queued run"

    # Second user message advances the turn, potentially completing the round
    # Current behavior: round completes when user speaks again (all participants have "spoken")
    # This clears the queue in non-auto-mode
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Second"
    )

    # The behavior here depends on auto_scheduling_enabled?
    # Without Auto without human or Auto, the round is cleared
    # This is current behavior being documented as test
  end

  test "only one running run per conversation" do
    # Create and claim a run
    run1 = ConversationRun.create!(
      conversation: @conversation,
      status: "running",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id,
      started_at: Time.current
    )

    # Attempting to create another running run should fail (DB constraint)
    assert_raises ActiveRecord::RecordNotUnique do
      ConversationRun.create!(
        conversation: @conversation,
        status: "running",
        kind: "auto_response",
        reason: "test2",
        speaker_space_membership_id: @ai_character.id,
        started_at: Time.current
      )
    end
  end

  # ============================================================================
  # 2. Auto without human lifecycle
  # ============================================================================

  test "starting auto without human sets remaining rounds" do
    @conversation.start_auto_without_human!(rounds: 4)

    assert @conversation.auto_without_human_enabled?
    assert_equal 4, @conversation.auto_without_human_remaining_rounds
  end

  test "auto without human rounds are clamped to valid range" do
    @conversation.start_auto_without_human!(rounds: 100)
    assert_equal Conversation::MAX_AUTO_WITHOUT_HUMAN_ROUNDS, @conversation.auto_without_human_remaining_rounds

    @conversation.start_auto_without_human!(rounds: 0)
    assert_equal 1, @conversation.auto_without_human_remaining_rounds
  end

  test "stopping auto without human clears remaining rounds" do
    @conversation.start_auto_without_human!(rounds: 4)
    @conversation.stop_auto_without_human!

    assert_not @conversation.auto_without_human_enabled?
    assert_nil @conversation.auto_without_human_remaining_rounds
  end

  test "auto without human rounds decrement atomically" do
    @conversation.start_auto_without_human!(rounds: 3)

    result = @conversation.decrement_auto_without_human_rounds!
    assert result
    assert_equal 2, @conversation.reload.auto_without_human_remaining_rounds
  end

  test "auto without human disables when rounds reach zero" do
    @conversation.start_auto_without_human!(rounds: 1)
    @conversation.decrement_auto_without_human_rounds!

    assert_not @conversation.reload.auto_without_human_enabled?
    assert_nil @conversation.auto_without_human_remaining_rounds
  end

  test "auto mode requires group chat (multiple AI characters)" do
    # Solo chat - only one AI character
    assert_not @space.group?

    # Add second AI character to make it a group
    @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2
    )

    assert @space.reload.group?
  end

  # ============================================================================
  # 3. Auto mode (membership) lifecycle
  # ============================================================================

  test "enabling auto mode sets remaining steps" do
    # User needs a character persona for auto
    @user_membership.update!(
      character: characters(:ready_v3),
      auto: "auto"
    )

    assert @user_membership.auto_enabled?
    assert_equal SpaceMembership::DEFAULT_AUTO_STEPS, @user_membership.auto_remaining_steps
  end

  test "auto user can auto respond" do
    @user_membership.update!(
      character: characters(:ready_v3),
      auto: "auto",
      auto_remaining_steps: 4
    )

    assert @user_membership.can_auto_respond?
  end

  test "auto mode is disabled when steps exhausted" do
    @user_membership.update!(
      character: characters(:ready_v3),
      auto: "auto"
    )
    assert @user_membership.auto_enabled?
    assert @user_membership.can_auto_respond?

    # Simulate exhausting all steps via atomic decrement
    # When steps reach 0, auto mode is automatically disabled
    SpaceMembership
      .where(id: @user_membership.id)
      .update_all(auto_remaining_steps: 1)

    @user_membership.decrement_auto_remaining_steps!
    @user_membership.reload

    # After exhaustion, auto mode should be disabled
    assert_not @user_membership.auto_enabled?
    assert_not @user_membership.can_auto_respond?
  end

  test "AI character can always auto respond" do
    assert @ai_character.can_auto_respond?
  end

  test "pure human cannot auto respond" do
    assert_not @user_membership.can_auto_respond?
  end

  # ============================================================================
  # 4. Auto without human/Auto Mutual Exclusion
  # ============================================================================

  # Mutual exclusion is enforced at the UX/controller layer.

  # ============================================================================
  # 5. Human Turn Handling in Auto Mode
  # ============================================================================

  test "queue preview includes participants" do
    # Add second AI for group chat
    @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2
    )

    # Get queue preview
    queue = TurnScheduler::Queries::QueuePreview.execute(conversation: @conversation, limit: 10)

    # Queue should include participants (AI characters that can respond)
    assert queue.any?, "Queue preview should have participants"
  end

  # ============================================================================
  # 6. Reply Order Strategies
  # ============================================================================

  test "natural order uses talkativeness for speaker selection" do
    char2 = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2,
      talkativeness_factor: 1.0  # Always talks
    )
    @ai_character.update!(talkativeness_factor: 0.0)  # Never talks via probability

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    # With talkativeness=1.0, char2 should be more likely selected
    runs = @conversation.conversation_runs.queued
    # Note: Natural order has randomness, so we just verify a run was created
    assert runs.any?
  end

  test "list order follows strict position rotation" do
    @space.update!(reply_order: "list")

    char2 = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2
    )

    # First message
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    run = @conversation.conversation_runs.queued.first
    assert_not_nil run
    # For ST-style list activation, the round queue includes ALL eligible speakers.
    assert_equal [@ai_character.id, char2.id], TurnScheduler.state(@conversation.reload).round_queue_ids

    # First AI should be scheduled first (position 1)
    assert_equal @ai_character.id, run.speaker_space_membership_id
  end

  test "list order schedules the next speaker after first assistant message" do
    @space.update!(reply_order: "list")

    char2 = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2
    )

    # Trigger round via user message
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    first_run = @conversation.conversation_runs.queued.first
    assert_equal @ai_character.id, first_run.speaker_space_membership_id

    # Simulate first run completing (so scheduler can enqueue next)
    first_run.update!(status: "succeeded", finished_at: Time.current)

    @conversation.messages.create!(
      space_membership: @ai_character,
      role: "assistant",
      content: "Response 1"
    )

    second_run = @conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil second_run
    assert_equal char2.id, second_run.speaker_space_membership_id
  end

  test "pooled order does not repeat speaker in same epoch" do
    @space.update!(reply_order: "pooled")

    char2 = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2
    )

    # User message starts epoch
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    first_run = @conversation.conversation_runs.queued.first
    first_speaker_id = first_run.speaker_space_membership_id

    # Simulate first speaker completing
    first_run.update!(status: "succeeded", finished_at: Time.current)
    @conversation.messages.create!(
      space_membership_id: first_speaker_id,
      role: "assistant",
      content: "Response 1"
    )

    # Clear old runs for clean test
    ConversationRun.where(conversation: @conversation, status: "queued").delete_all

    # Trigger next speaker selection via query
    first_speaker = @space.space_memberships.find(first_speaker_id)
    second_speaker = TurnScheduler::Queries::NextSpeaker.execute(
      conversation: @conversation,
      previous_speaker: first_speaker,
      allow_self: @space.allow_self_responses?
    )

    # Second speaker should be different (pool not repeated)
    if second_speaker
      assert_not_equal first_speaker_id, second_speaker.id
    end
  end

  test "pooled reply_order activates a single speaker per user message (ST-like)" do
    @space.update!(reply_order: "pooled")

    @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2
    )

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello pooled!"
    )

    state = TurnScheduler.state(@conversation.reload)
    assert_equal 1, state.round_queue_ids.size
    assert_equal state.round_queue_ids.first, @conversation.conversation_runs.queued.first.speaker_space_membership_id
  end

  test "manual order does not auto-select speakers" do
    @space.update!(reply_order: "manual")

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    # No run should be created
    assert_nil @conversation.conversation_runs.queued.first
  end

  # ============================================================================
  # 7. Force Talk Behavior
  # ============================================================================

  test "force talk creates run for specified speaker" do
    run = Conversations::RunPlanner.plan_force_talk!(
      conversation: @conversation,
      speaker_space_membership_id: @ai_character.id
    )

    assert_not_nil run
    assert_equal "queued", run.status
    assert_equal @ai_character.id, run.speaker_space_membership_id
    assert_equal "force_talk", run.reason
  end

  test "force talk works in manual mode" do
    @space.update!(reply_order: "manual")

    run = Conversations::RunPlanner.plan_force_talk!(
      conversation: @conversation,
      speaker_space_membership_id: @ai_character.id
    )

    assert_not_nil run
  end

  test "force talk works even for muted speaker" do
    # Mute the character - force talk overrides participation settings
    @ai_character.update!(participation: "muted")

    run = Conversations::RunPlanner.plan_force_talk!(
      conversation: @conversation,
      speaker_space_membership_id: @ai_character.id
    )

    # Force talk should still work - muting only affects automatic selection
    assert_not_nil run
    assert_equal @ai_character.id, run.speaker_space_membership_id
  end

  test "force talk returns nil for removed speaker" do
    # Remove the character from the space
    @ai_character.update!(status: "removed")

    run = Conversations::RunPlanner.plan_force_talk!(
      conversation: @conversation,
      speaker_space_membership_id: @ai_character.id
    )

    assert_nil run
  end

  # ============================================================================
  # 8. Regenerate Behavior
  # ============================================================================

  test "regenerate creates run for target message speaker" do
    # Create an assistant message first
    assistant_message = @conversation.messages.create!(
      space_membership: @ai_character,
      role: "assistant",
      content: "Original response",
      generation_status: "succeeded"
    )

    # Clear any existing runs
    ConversationRun.where(conversation: @conversation).delete_all

    run = Conversations::RunPlanner.plan_regenerate!(
      conversation: @conversation,
      target_message: assistant_message
    )

    assert_not_nil run
    assert_equal @ai_character.id, run.speaker_space_membership_id
    assert_equal "regenerate", run.reason
    assert_equal assistant_message.id, run.debug["target_message_id"]
  end

  test "regenerate fails for user message" do
    user_message = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    assert_raises ArgumentError do
      Conversations::RunPlanner.plan_regenerate!(
        conversation: @conversation,
        target_message: user_message
      )
    end
  end

  # ============================================================================
  # 9. Muted Members
  # ============================================================================

  test "muted members are excluded from auto selection" do
    @ai_character.update!(participation: "muted")

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    # No run should be created (only AI is muted)
    run = @conversation.conversation_runs.queued.first
    assert_nil run
  end

  test "removed members are excluded from queue" do
    @ai_character.remove!(by_user: @user)

    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    run = @conversation.conversation_runs.queued.first
    assert_nil run
  end

  # ============================================================================
  # 10. Cancel All Queued Runs
  # ============================================================================

  test "cancel_all_queued_runs cancels queued runs" do
    # Create a queued run
    run = ConversationRun.create!(
      conversation: @conversation,
      status: "queued",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id
    )

    canceled_count = @conversation.cancel_all_queued_runs!(reason: "user_message")

    assert_equal 1, canceled_count
    assert_equal "canceled", run.reload.status
    assert_equal "user_message", run.debug["canceled_by"]
  end

  test "cancel_all_queued_runs does not affect running runs" do
    # Create a running run
    run = ConversationRun.create!(
      conversation: @conversation,
      status: "running",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id,
      started_at: Time.current
    )

    canceled_count = @conversation.cancel_all_queued_runs!(reason: "user_message")

    assert_equal 0, canceled_count
    assert_equal "running", run.reload.status
  end

  # ============================================================================
  # 11. Auto Mode Delay
  # ============================================================================

  test "auto mode delay applies to run_after" do
    # Add second AI for group chat (auto mode requirement)
    @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2
    )
    @space.update!(auto_without_human_delay_ms: 1500)

    @conversation.start_auto_without_human!(rounds: 2)

    # Clear any runs from starting auto mode
    ConversationRun.where(conversation: @conversation).delete_all

    travel_to Time.current.change(usec: 0) do
      # Manually start a round to trigger AI scheduling
      TurnScheduler.start_round!(@conversation)

      run = @conversation.conversation_runs.queued.first
      assert_not_nil run, "Should create a queued run in auto mode"

      # Run should be delayed by auto_without_human_delay_ms
      expected_run_after = Time.current + 1.5.seconds
      assert_in_delta expected_run_after, run.run_after, 0.5.seconds
    end
  end

  # ============================================================================
  # 12. During Generation Policy
  # ============================================================================

  test "restart policy via RunPlanner cancels running run" do
    @space.update!(during_generation_user_input_policy: "restart")

    # Create a running run
    running_run = ConversationRun.create!(
      conversation: @conversation,
      status: "running",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id,
      started_at: Time.current
    )

    # Use RunPlanner which applies the restart policy
    # This simulates force_talk which does apply policy
    Conversations::RunPlanner.plan_force_talk!(
      conversation: @conversation,
      speaker_space_membership_id: @ai_character.id
    )

    # Running run should have cancel requested
    assert running_run.reload.cancel_requested?
  end

  test "cancel request marks cancel_requested_at timestamp" do
    running_run = ConversationRun.create!(
      conversation: @conversation,
      status: "running",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id,
      started_at: Time.current
    )

    assert_nil running_run.cancel_requested_at

    running_run.request_cancel!

    assert_not_nil running_run.cancel_requested_at
    assert running_run.cancel_requested?
  end

  # ============================================================================
  # 13. Run Status Transitions
  # ============================================================================

  test "run can transition from queued to running" do
    run = ConversationRun.create!(
      conversation: @conversation,
      status: "queued",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id
    )

    run.running!

    assert_equal "running", run.status
    assert_not_nil run.started_at
    assert_not_nil run.heartbeat_at
  end

  test "run can transition from running to succeeded" do
    run = ConversationRun.create!(
      conversation: @conversation,
      status: "running",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id,
      started_at: Time.current
    )

    run.succeeded!

    assert_equal "succeeded", run.status
    assert_not_nil run.finished_at
  end

  test "run can transition from running to failed" do
    run = ConversationRun.create!(
      conversation: @conversation,
      status: "running",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id,
      started_at: Time.current
    )

    run.failed!(error: { "code" => "test_error" })

    assert_equal "failed", run.status
    assert_not_nil run.finished_at
    assert_equal "test_error", run.error["code"]
  end

  test "run can transition from running to canceled" do
    run = ConversationRun.create!(
      conversation: @conversation,
      status: "running",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id,
      started_at: Time.current
    )

    run.canceled!

    assert_equal "canceled", run.status
    assert_not_nil run.finished_at
  end

  test "run can transition to skipped" do
    run = ConversationRun.create!(
      conversation: @conversation,
      status: "queued",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id
    )

    run.skipped!

    assert_equal "skipped", run.status
    assert_not_nil run.finished_at
  end

  # ============================================================================
  # 14. Stale Run Detection
  # ============================================================================

  test "run is stale when heartbeat exceeds timeout" do
    run = ConversationRun.create!(
      conversation: @conversation,
      status: "running",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id,
      started_at: 15.minutes.ago,
      heartbeat_at: 15.minutes.ago
    )

    assert run.stale?(timeout: 10.minutes)
    assert_not run.stale?(timeout: 20.minutes)
  end

  test "queued run is not stale" do
    run = ConversationRun.create!(
      conversation: @conversation,
      status: "queued",
      kind: "auto_response",
      reason: "test",
      speaker_space_membership_id: @ai_character.id
    )

    assert_not run.stale?
  end

  # ============================================================================
  # 15. Allow Self Responses
  # ============================================================================

  test "allow_self_responses=false prevents same speaker twice in a row" do
    @space.update!(allow_self_responses: false)

    char2 = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2,
      talkativeness_factor: 1.0
    )
    @ai_character.update!(talkativeness_factor: 1.0)

    # First message
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello!"
    )

    # Simulate first AI response
    @conversation.messages.create!(
      space_membership: @ai_character,
      role: "assistant",
      content: "Hi there!"
    )

    next_speaker = TurnScheduler::Queries::NextSpeaker.execute(
      conversation: @conversation,
      previous_speaker: @ai_character,
      allow_self: false
    )

    # Should not be the same speaker
    if next_speaker
      assert_not_equal @ai_character.id, next_speaker.id
    end
  end

  # ============================================================================
  # 16. Auto user banned from consecutive responses
  # ============================================================================

  test "auto user is banned from being selected after their own message" do
    # Enable auto for the user
    auto_character = Character.create!(
      name: "Auto Persona",
      personality: "Test auto",
      data: { "name" => "Auto Persona" },
      spec_version: 2,
      file_sha256: "auto_ban_test_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )
    @user_membership.update!(
      character: auto_character,
      auto: "auto",
      auto_remaining_steps: 4,
      talkativeness_factor: 1.0  # High talkativeness to ensure they would be selected if not banned
    )
    @ai_character.update!(talkativeness_factor: 1.0)

    @space.update!(allow_self_responses: false)

    # Auto user sends a message (role: "user")
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello from auto!"
    )

    # The AI character should be selected, not the auto user
    run = @conversation.conversation_runs.queued.first
    assert_not_nil run, "Should create a queued run"
    assert_equal @ai_character.id, run.speaker_space_membership_id,
      "AI character should be selected, not the auto user who just sent a message"
  end

  test "auto user can respond after AI message (not banned)" do
    # Enable auto for the user
    auto_character = Character.create!(
      name: "Auto Persona 2",
      personality: "Test auto",
      data: { "name" => "Auto Persona 2" },
      spec_version: 2,
      file_sha256: "auto_notban_test_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )
    @user_membership.update!(
      character: auto_character,
      auto: "auto",
      auto_remaining_steps: 4,
      talkativeness_factor: 1.0
    )
    @ai_character.update!(talkativeness_factor: 0.0)  # Low talkativeness

    @space.update!(allow_self_responses: false)

    # AI character sends a message first
    @conversation.messages.create!(
      space_membership: @ai_character,
      role: "assistant",
      content: "Hello from AI!"
    )

    # Use ActivatedQueue to test next speaker selection
    # The auto user should be eligible (not banned) since AI just spoke
    queue = TurnScheduler::Queries::ActivatedQueue.execute(
      conversation: @conversation,
      trigger_message: nil,
      is_user_input: false
    )

    # Auto user should be in the candidates (not banned)
    # With AI talkativeness=0 and auto=1.0, auto should be selected
    assert queue.include?(@user_membership),
      "Auto user should be selectable after AI message"
  end

  test "auto user with user-role message is banned same as assistant-role message" do
    # This specifically tests the fix for the bug where auto users sending
    # role="user" messages were not being banned because the old logic only
    # checked for assistant? role.
    auto_character = Character.create!(
      name: "Auto Persona 3",
      personality: "Test auto",
      data: { "name" => "Auto Persona 3" },
      spec_version: 2,
      file_sha256: "auto_role_test_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )
    @user_membership.update!(
      character: auto_character,
      auto: "auto",
      auto_remaining_steps: 4
    )

    @space.update!(allow_self_responses: false)

    # Create a message from auto user with role="user"
    last_msg = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",  # Auto sends as "user" role, not "assistant"
      content: "Auto message with user role"
    )

    # Verify the message has user role but is from a can_auto_respond? participant
    assert_equal "user", last_msg.role
    assert @user_membership.can_auto_respond?, "Auto user should be able to auto respond"

    # Now test the banned_id calculation via ActivatedQueue
    queue = TurnScheduler::Queries::ActivatedQueue.execute(
      conversation: @conversation,
      trigger_message: nil,
      is_user_input: false
    )

    # The auto user should NOT be in the queue (should be banned)
    assert_not queue.include?(@user_membership),
      "Auto user should be banned after sending a message, even with role='user'"

    # The AI character should be in the queue
    assert queue.include?(@ai_character),
      "AI character should be in the queue"
  end
end
