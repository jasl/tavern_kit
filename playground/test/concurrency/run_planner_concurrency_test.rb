# frozen_string_literal: true

require "test_helper"

# Tests for RunPlanner concurrent access patterns.
#
# These tests verify that the optimistic concurrency implementation
# correctly handles race conditions without data corruption.
#
# Focus: Testing the database-level concurrency safety, not business logic.
#
class RunPlannerConcurrencyTest < ActiveSupport::TestCase
  setup do
    # Pre-seed default settings to avoid race conditions in parallel tests
    Setting.set("llm.default_provider_id", LLMProvider.first&.id || "1") if Setting.find_by(key: "llm.default_provider_id").nil?
    Setting.set("preset.default_id", Preset.first&.id || "1") if Setting.find_by(key: "preset.default_id").nil?

    @user = users(:admin)
    @space = Spaces::Playground.create!(name: "Concurrency Test Space", owner: @user)

    @ai_char = characters(:ready_v2)
    @ai_membership = @space.space_memberships.create!(
      character: @ai_char,
      kind: "character",
      role: "member",
      status: "active",
      participation: "active"
    )

    @user_membership = @space.space_memberships.find_by(user: @user)

    @conversation = @space.conversations.create!(title: "Concurrency Test")
  end

  # ============================================================
  # Core Concurrency Test: Unique Index Enforcement
  # ============================================================

  test "database unique index prevents duplicate queued runs" do
    # This test directly verifies the unique partial index behavior
    ConversationRun.where(conversation: @conversation).delete_all

    barrier = Concurrent::CyclicBarrier.new(5)
    results = Concurrent::Array.new

    # Concurrently try to create queued runs directly (bypassing business logic)
    5.times.map do |i|
      Thread.new do
        barrier.wait

        run = @conversation.conversation_runs.create!(
          kind: "user_turn",
          status: "queued",
          reason: "test_#{i}",
          speaker_space_membership: @ai_membership,
          run_after: Time.current
        )
        results << { success: true, id: run.id }
      rescue ActiveRecord::RecordNotUnique
        results << { success: false, reason: :unique_violation }
      rescue => e
        results << { success: false, error: e.message }
      end
    end.each(&:join)

    # Exactly one should succeed due to unique partial index
    successes = results.select { |r| r[:success] }
    unique_violations = results.select { |r| r[:reason] == :unique_violation }

    assert_equal 1, successes.count, "Exactly one create should succeed"
    assert_equal 4, unique_violations.count, "Other creates should get unique violation"

    # Verify only one queued run exists
    assert_equal 1, ConversationRun.queued.where(conversation: @conversation).count
  end

  test "upsert_queued_run handles concurrent access gracefully" do
    # This test verifies that upsert_queued_run! correctly handles the
    # RecordNotUnique exception and falls back to update
    ConversationRun.where(conversation: @conversation).delete_all

    barrier = Concurrent::CyclicBarrier.new(5)
    results = Concurrent::Array.new

    5.times.map do |i|
      Thread.new do
        barrier.wait

        # Call the private method directly via send (for testing purposes)
        run = Conversation::RunPlanner.send(
          :upsert_queued_run!,
          conversation: @conversation,
          kind: "user_turn",
          reason: "test_#{i}",
          speaker_space_membership_id: @ai_membership.id,
          run_after: Time.current,
          debug: { thread: i }
        )
        results << { success: true, id: run.id }
      rescue => e
        results << { success: false, error: e.message }
      end
    end.each(&:join)

    # All should succeed (either create or update)
    assert results.all? { |r| r[:success] }, "All upserts should succeed: #{results.reject { |r| r[:success] }.inspect}"

    # All should return the same run ID
    ids = results.map { |r| r[:id] }.uniq
    assert_equal 1, ids.count, "All results should reference the same run"

    # Verify only one queued run exists
    assert_equal 1, ConversationRun.queued.where(conversation: @conversation).count
  end

  test "create_exclusive_queued_run only allows first winner" do
    # This test verifies that create_exclusive_queued_run! correctly
    # returns nil for losers when a run already exists
    ConversationRun.where(conversation: @conversation).delete_all

    barrier = Concurrent::CyclicBarrier.new(5)
    results = Concurrent::Array.new

    5.times.map do |i|
      Thread.new do
        barrier.wait

        # Call the private method directly via send (for testing purposes)
        run = Conversation::RunPlanner.send(
          :create_exclusive_queued_run!,
          conversation: @conversation,
          kind: "auto_mode",
          reason: "test_#{i}",
          speaker_space_membership_id: @ai_membership.id,
          run_after: Time.current,
          debug: { thread: i }
        )
        results << { success: run.present?, run_id: run&.id }
      rescue => e
        results << { success: false, error: e.message }
      end
    end.each(&:join)

    # Check no errors occurred
    errors = results.select { |r| r[:error] }
    assert errors.empty?, "No errors should occur: #{errors.inspect}"

    # Exactly one should succeed
    successes = results.select { |r| r[:success] }
    assert_equal 1, successes.count, "Exactly one create_exclusive should succeed"

    # Others should return nil (not error)
    nils = results.reject { |r| r[:success] }
    assert_equal 4, nils.count

    # Verify only one queued run exists
    assert_equal 1, ConversationRun.queued.where(conversation: @conversation).count
  end

  # ============================================================
  # Running Run Cancellation
  # ============================================================

  test "concurrent regenerate requests all request cancellation" do
    # Create a running run
    running_run = @conversation.conversation_runs.create!(
      kind: "user_turn",
      status: "running",
      reason: "user_message",
      speaker_space_membership: @ai_membership,
      started_at: Time.current
    )

    # Create a target message for regeneration
    target_message = @conversation.messages.create!(
      space_membership: @ai_membership,
      role: "assistant",
      content: "Original response"
    )

    barrier = Concurrent::CyclicBarrier.new(3)
    3.times.map do
      Thread.new do
        barrier.wait

        Conversation::RunPlanner.plan_regenerate!(
          conversation: @conversation.reload,
          target_message: target_message
        )
      end
    end.each(&:join)

    # Running run should have cancel requested
    running_run.reload
    assert running_run.cancel_requested_at.present?, "Running run should have cancel_requested_at set"

    # Should have exactly one queued regenerate run
    queued = ConversationRun.queued.where(conversation: @conversation)
    assert_equal 1, queued.count
    assert_equal "regenerate", queued.first.kind
  end
end
