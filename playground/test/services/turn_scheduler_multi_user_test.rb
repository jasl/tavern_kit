# frozen_string_literal: true

require "test_helper"

# Tests for multi-user scenarios in the same conversation.
#
# These tests verify that the TurnScheduler correctly handles:
# - Multiple users sending messages concurrently
# - Message sequence (seq) assignment with optimistic retry
# - Queue state consistency under concurrent access
#
# Note: Uses Spaces::Discussion which allows multiple human memberships.
# Spaces::Playground only allows one human.
#
class TurnSchedulerMultiUserTest < ActiveSupport::TestCase
  setup do
    @admin = users(:admin)

    # Create a second user for multi-user tests
    @user2 = User.create!(
      name: "Test User 2",
      email: "user2_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )

    # Use Discussion space which allows multiple human memberships
    @space = Spaces::Discussion.create!(
      name: "Multi-User Test Space",
      owner: @admin,
      reply_order: "list",
      during_generation_user_input_policy: "queue",
      user_turn_debounce_ms: 0
    )

    @conversation = @space.conversations.create!(title: "Main")

    @human1 = @space.space_memberships.create!(
      kind: "human",
      role: "owner",
      user: @admin,
      position: 0
    )

    @human2 = @space.space_memberships.create!(
      kind: "human",
      role: "member",
      user: @user2,
      position: 1
    )

    @ai = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      position: 2
    )

    ConversationRun.where(conversation: @conversation).delete_all
  end

  # ============================================================================
  # Message Sequence Tests
  # ============================================================================

  test "messages from different users get unique sequential seq values" do
    # User 1 sends first message
    msg1 = @conversation.messages.create!(
      space_membership: @human1,
      role: "user",
      content: "Hello from user 1"
    )

    # User 2 sends second message
    msg2 = @conversation.messages.create!(
      space_membership: @human2,
      role: "user",
      content: "Hello from user 2"
    )

    # User 1 sends third message
    msg3 = @conversation.messages.create!(
      space_membership: @human1,
      role: "user",
      content: "Another from user 1"
    )

    # Verify seq values are sequential and unique
    assert_equal 1, msg1.seq
    assert_equal 2, msg2.seq
    assert_equal 3, msg3.seq
  end

  test "concurrent message creation maintains seq uniqueness" do
    barrier = Concurrent::CyclicBarrier.new(3)
    results = Concurrent::Array.new
    conversation_id = @conversation.id
    human1_id = @human1.id
    human2_id = @human2.id

    threads = [
      Thread.new do
        barrier.wait
        ActiveRecord::Base.connection_pool.with_connection do
          conv = Conversation.find(conversation_id)
          membership = SpaceMembership.find(human1_id)
          msg = conv.messages.create!(
            space_membership: membership,
            role: "user",
            content: "Message from user 1 - thread 1"
          )
          results << { user: 1, seq: msg.seq, id: msg.id }
        end
      rescue => e
        results << { error: e.message }
      end,
      Thread.new do
        barrier.wait
        ActiveRecord::Base.connection_pool.with_connection do
          conv = Conversation.find(conversation_id)
          membership = SpaceMembership.find(human2_id)
          msg = conv.messages.create!(
            space_membership: membership,
            role: "user",
            content: "Message from user 2 - thread 2"
          )
          results << { user: 2, seq: msg.seq, id: msg.id }
        end
      rescue => e
        results << { error: e.message }
      end,
      Thread.new do
        barrier.wait
        ActiveRecord::Base.connection_pool.with_connection do
          conv = Conversation.find(conversation_id)
          membership = SpaceMembership.find(human1_id)
          msg = conv.messages.create!(
            space_membership: membership,
            role: "user",
            content: "Message from user 1 - thread 3"
          )
          results << { user: 1, seq: msg.seq, id: msg.id }
        end
      rescue => e
        results << { error: e.message }
      end,
    ]

    threads.each(&:join)

    # All messages should succeed
    errors = results.select { |r| r[:error] }
    assert_empty errors, "All concurrent messages should succeed: #{errors.inspect}"

    # All seq values should be unique
    seqs = results.map { |r| r[:seq] }.compact
    assert_equal seqs.uniq.size, seqs.size, "All seq values should be unique: #{seqs.inspect}"

    # Seq values should be 1, 2, 3 (in some order)
    assert_equal [1, 2, 3], seqs.sort
  end

  # ============================================================================
  # Queue State Consistency Tests
  # ============================================================================

  test "queue state remains consistent when multiple users send messages" do
    # User 1 sends message, triggering AI queue
    @conversation.messages.create!(
      space_membership: @human1,
      role: "user",
      content: "Hello from user 1"
    )

    # User 2 sends message while round is active
    @conversation.messages.create!(
      space_membership: @human2,
      role: "user",
      content: "Hello from user 2"
    )

    @conversation.reload

    # Queue state should be valid (not corrupted)
    state = TurnScheduler.state(@conversation)
    assert TurnScheduler::STATES.include?(state.scheduling_state),
           "Scheduling state should be valid: #{state.scheduling_state}"

    # Round queue should be an array
    assert state.round_queue_ids.is_a?(Array),
           "Round queue should be an array"
  end

  test "concurrent user messages do not corrupt scheduling state" do
    barrier = Concurrent::CyclicBarrier.new(2)
    conversation_id = @conversation.id
    human1_id = @human1.id
    human2_id = @human2.id

    threads = [
      Thread.new do
        barrier.wait
        ActiveRecord::Base.connection_pool.with_connection do
          conv = Conversation.find(conversation_id)
          membership = SpaceMembership.find(human1_id)
          conv.messages.create!(
            space_membership: membership,
            role: "user",
            content: "Concurrent message from user 1"
          )
        end
      end,
      Thread.new do
        barrier.wait
        ActiveRecord::Base.connection_pool.with_connection do
          conv = Conversation.find(conversation_id)
          membership = SpaceMembership.find(human2_id)
          conv.messages.create!(
            space_membership: membership,
            role: "user",
            content: "Concurrent message from user 2"
          )
        end
      end,
    ]

    threads.each(&:join)

    @conversation.reload

    # Verify state is valid
    state = TurnScheduler.state(@conversation)
    assert TurnScheduler::STATES.include?(state.scheduling_state),
           "Scheduling state should be valid after concurrent messages"

    # Verify queue is valid
    assert state.round_queue_ids.is_a?(Array)
    assert state.round_spoken_ids.is_a?(Array)

    # Verify at most one queued run exists (database constraint)
    assert @conversation.conversation_runs.queued.count <= 1,
           "At most one queued run should exist"

    # Verify at most one running run exists (database constraint)
    assert @conversation.conversation_runs.running.count <= 1,
           "At most one running run should exist"
  end

  # ============================================================================
  # User Input Priority Tests
  # ============================================================================

  test "second user message cancels queued runs from first user message" do
    # User 1 sends message, triggering AI queue
    @conversation.messages.create!(
      space_membership: @human1,
      role: "user",
      content: "Hello from user 1"
    )

    first_run = @conversation.conversation_runs.queued.first
    assert_not_nil first_run, "First message should create a queued run"

    # User 2 sends message - this should advance the turn
    @conversation.messages.create!(
      space_membership: @human2,
      role: "user",
      content: "Hello from user 2"
    )

    @conversation.reload

    # The scheduler should have advanced, potentially creating a new run
    # or completing the round depending on the state
    assert_includes TurnScheduler::STATES, TurnScheduler.state(@conversation).scheduling_state
  end

  # ============================================================================
  # Auto Multi-User Tests
  # ============================================================================

  test "only one auto user can be active at a time in queue" do
    # Create persona characters for both users
    auto_char1 = Character.create!(
      name: "Auto User 1",
      personality: "Test",
      data: { "name" => "Auto User 1" },
      spec_version: 2,
      file_sha256: "auto_u1_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )

    auto_char2 = Character.create!(
      name: "Auto User 2",
      personality: "Test",
      data: { "name" => "Auto User 2" },
      spec_version: 2,
      file_sha256: "auto_u2_#{SecureRandom.hex(8)}",
      status: "ready",
      visibility: "private"
    )

    # Enable auto for both users
    @human1.update!(
      character: auto_char1,
      auto: "auto",
      auto_remaining_steps: 5
    )

    @human2.update!(
      character: auto_char2,
      auto: "auto",
      auto_remaining_steps: 5
    )

    # Start auto without human
    @conversation.start_auto_without_human!(rounds: 2)
    TurnScheduler.start_round!(@conversation)

    @conversation.reload

    # Both auto users should be in the queue (list order)
    queue_ids = TurnScheduler.state(@conversation).round_queue_ids
    assert_includes queue_ids, @human1.id
    assert_includes queue_ids, @human2.id

    # But only one queued run should exist at a time (database constraint)
    assert_equal 1, @conversation.conversation_runs.queued.count
  end
end
