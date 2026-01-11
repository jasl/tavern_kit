# frozen_string_literal: true

require "test_helper"

# Fence tests for the self-owned event store layer (RES-inspired, but custom).
#
# These tests intentionally define the concurrency + ordering contract we rely on
# to prevent multi-process UI out-of-order updates and "stuck" scheduling.
class ConversationEngineEventStoreConcurrencyTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(name: "ES Fence Space", owner: @user)
    @conversation = @space.conversations.create!(title: "Main")
  end

  test "append enforces optimistic concurrency via expected_version (CAS)" do
    # When multiple writers attempt to append at the same expected_version,
    # exactly one should succeed and others must receive a conflict.

    barrier = Concurrent::CyclicBarrier.new(5)
    results = Concurrent::Array.new

    5.times.map do |i|
      Thread.new do
        barrier.wait
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            ConversationEngine::EventStore.append!(
              conversation_id: @conversation.id,
              expected_version: -1,
              events: [
                {
                  type: "test.event",
                  payload: { "i" => i },
                  meta: { "test" => true },
                },
              ]
            )
            results << { ok: true }
          rescue ConversationEngine::Errors::ConcurrencyConflict
            results << { ok: false, conflict: true }
          end
        end
      end
    end.each(&:join)

    assert_equal 1, results.count { |r| r[:ok] }, "Expected exactly one winner"
    assert_equal 4, results.count { |r| r[:conflict] }, "Expected other writers to conflict"
  end

  test "append allocates contiguous versions for a single conversation" do
    ConversationEngine::EventStore.append!(
      conversation_id: @conversation.id,
      expected_version: -1,
      events: [
        { type: "test.one", payload: {}, meta: {} },
        { type: "test.two", payload: {}, meta: {} },
        { type: "test.three", payload: {}, meta: {} },
      ]
    )

    events = ConversationEngine::EventStore.read(conversation_id: @conversation.id).to_a
    assert_equal %w[test.one test.two test.three], events.map(&:type)
    assert_equal [0, 1, 2], events.map(&:version)
  end
end
