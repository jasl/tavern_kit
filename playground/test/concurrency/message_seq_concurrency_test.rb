# frozen_string_literal: true

require "test_helper"

# Tests for Message seq assignment concurrent access patterns.
#
# These tests verify that the optimistic retry implementation
# correctly assigns unique sequence numbers without gaps or duplicates.
#
class MessageSeqConcurrencyTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(name: "Seq Test Space", owner: @user)

    @membership = @space.space_memberships.create!(
      user: @user,
      role: "member",
      status: "active"
    )

    @conversation = @space.conversations.create!(title: "Seq Test Conversation")
  end

  # ============================================================
  # Concurrent Message Creation - Unique Seq Values
  # ============================================================

  test "concurrent message creation assigns unique seq values" do
    # Create messages concurrently
    message_count = 20
    barrier = Concurrent::CyclicBarrier.new(message_count)
    messages = Concurrent::Array.new
    conversation_id = @conversation.id
    membership_id = @membership.id

    threads = message_count.times.map do |i|
      Thread.new do
        barrier.wait

        ActiveRecord::Base.connection_pool.with_connection do
          msg = Message.create!(
            conversation_id: conversation_id,
            space_membership_id: membership_id,
            role: "user",
            content: "Concurrent message #{i}"
          )
          messages << msg
        end
      rescue => e
        messages << e
      end
    end

    threads.each(&:join)

    # Check for errors
    errors = messages.select { |m| m.is_a?(Exception) }
    assert errors.empty?, "No errors should occur: #{errors.map(&:message).join(', ')}"

    # All messages should be created
    created_messages = messages.reject { |m| m.is_a?(Exception) }
    assert_equal message_count, created_messages.count, "All messages should be created"

    # All seq values should be unique
    seq_values = created_messages.map(&:seq)
    assert_equal seq_values.uniq.count, seq_values.count, "All seq values should be unique"

    # Seq values should be consecutive (no gaps) from 1 to message_count
    assert_equal (1..message_count).to_a.sort, seq_values.sort, "Seq values should be 1 to #{message_count}"
  end

  test "concurrent message creation with existing messages maintains seq continuity" do
    # Create some initial messages
    initial_count = 5
    initial_count.times do |i|
      @conversation.messages.create!(
        space_membership: @membership,
        role: "user",
        content: "Initial message #{i + 1}"
      )
    end

    # Create more messages concurrently
    concurrent_count = 10
    barrier = Concurrent::CyclicBarrier.new(concurrent_count)
    messages = Concurrent::Array.new
    conversation_id = @conversation.id
    membership_id = @membership.id

    threads = concurrent_count.times.map do |i|
      Thread.new do
        barrier.wait

        ActiveRecord::Base.connection_pool.with_connection do
          msg = Message.create!(
            conversation_id: conversation_id,
            space_membership_id: membership_id,
            role: "user",
            content: "Concurrent message #{i}"
          )
          messages << msg
        end
      rescue => e
        messages << e
      end
    end

    threads.each(&:join)

    # Check for errors
    errors = messages.select { |m| m.is_a?(Exception) }
    assert errors.empty?, "No errors should occur: #{errors.map(&:message).join(', ')}"

    # All messages should be created
    created_messages = messages.reject { |m| m.is_a?(Exception) }
    assert_equal concurrent_count, created_messages.count

    # Check all messages in conversation
    all_messages = @conversation.messages.reload.order(:seq)
    total_count = initial_count + concurrent_count

    assert_equal total_count, all_messages.count, "Total message count should match"

    # All seq values should be unique and consecutive
    seq_values = all_messages.map(&:seq)
    assert_equal (1..total_count).to_a, seq_values, "Seq values should be consecutive 1 to #{total_count}"
  end

  # ============================================================
  # High Contention Scenario
  # ============================================================

  test "high contention message creation handles retries correctly" do
    # Create many messages in rapid succession with high contention
    message_count = 50
    barrier = Concurrent::CyclicBarrier.new(message_count)
    results = Concurrent::Array.new
    conversation_id = @conversation.id
    membership_id = @membership.id

    threads = message_count.times.map do |i|
      Thread.new do
        barrier.wait

        ActiveRecord::Base.connection_pool.with_connection do
          msg = Message.create!(
            conversation_id: conversation_id,
            space_membership_id: membership_id,
            role: "user",
            content: "High contention message #{i}"
          )
          results << { success: true, message: msg }
        end
      rescue => e
        results << { success: false, error: e }
      end
    end

    threads.each(&:join)

    # Count successes and failures
    successes = results.select { |r| r[:success] }
    failures = results.reject { |r| r[:success] }

    # All should succeed (retry mechanism should handle conflicts)
    assert_equal message_count, successes.count, "All messages should be created successfully"
    assert failures.empty?, "No failures expected: #{failures.map { |f| f[:error].message }.join(', ')}"

    # Verify data integrity
    all_messages = @conversation.messages.reload
    seq_values = all_messages.map(&:seq).sort
    expected_seq = (1..message_count).to_a

    assert_equal expected_seq, seq_values, "Seq values should be consecutive without gaps"
  end

  # ============================================================
  # Cross-Conversation Isolation
  # ============================================================

  test "concurrent creation in different conversations does not interfere" do
    # Create a second conversation
    conversation2 = @space.conversations.create!(title: "Second Conversation")
    conversation1_id = @conversation.id
    conversation2_id = conversation2.id
    membership_id = @membership.id

    messages_per_conversation = 10
    total_threads = messages_per_conversation * 2
    barrier = Concurrent::CyclicBarrier.new(total_threads)
    results = Concurrent::Array.new

    threads = []

    # Create messages in conversation 1
    messages_per_conversation.times do |i|
      threads << Thread.new do
        barrier.wait

        ActiveRecord::Base.connection_pool.with_connection do
          msg = Message.create!(
            conversation_id: conversation1_id,
            space_membership_id: membership_id,
            role: "user",
            content: "Conv1 message #{i}"
          )
          results << { conversation_id: conversation1_id, message: msg }
        end
      rescue => e
        results << { error: e }
      end
    end

    # Create messages in conversation 2
    messages_per_conversation.times do |i|
      threads << Thread.new do
        barrier.wait

        ActiveRecord::Base.connection_pool.with_connection do
          msg = Message.create!(
            conversation_id: conversation2_id,
            space_membership_id: membership_id,
            role: "user",
            content: "Conv2 message #{i}"
          )
          results << { conversation_id: conversation2_id, message: msg }
        end
      rescue => e
        results << { error: e }
      end
    end

    threads.each(&:join)

    # Check for errors
    errors = results.select { |r| r[:error] }
    assert errors.empty?, "No errors should occur: #{errors.map { |r| r[:error].message }.join(', ')}"

    # Each conversation should have independent seq values 1..N
    conv1_seq = @conversation.messages.reload.pluck(:seq).sort
    conv2_seq = conversation2.messages.reload.pluck(:seq).sort

    assert_equal (1..messages_per_conversation).to_a, conv1_seq, "Conv1 seq should be 1 to #{messages_per_conversation}"
    assert_equal (1..messages_per_conversation).to_a, conv2_seq, "Conv2 seq should be 1 to #{messages_per_conversation}"
  end
end
