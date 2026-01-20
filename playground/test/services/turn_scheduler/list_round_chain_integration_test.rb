# frozen_string_literal: true

require "test_helper"

class TurnScheduler::ListRoundChainIntegrationTest < ActiveSupport::TestCase
  setup do
    ConversationChannel.stubs(:broadcast_typing)
    ConversationChannel.stubs(:broadcast_stream_chunk)
    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_run_error_alert)
    ConversationChannel.stubs(:broadcast_run_failed)

    TurnScheduler::Broadcasts.stubs(:queue_updated)

    Message.any_instance.stubs(:broadcast_create)
    Message.any_instance.stubs(:broadcast_update)
  end

  test "reply_order=list: user message triggers two AI runs in one round (serial)" do
    admin = users(:admin)

    space =
      Spaces::Playground.create!(
        name: "List round chain integration",
        owner: admin,
        reply_order: "list",
        allow_self_responses: false,
        auto_without_human_delay_ms: 0,
        user_turn_debounce_ms: 0
      )

    human =
      space.space_memberships.create!(
        kind: "human",
        role: "owner",
        user: admin,
        position: 0
      )

    ai1 =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v2),
        position: 1
      )

    ai2 =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v3),
        position: 2
      )

    conversation = space.conversations.create!(title: "Main", kind: "root")

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:last_usage) { nil }
    client.define_singleton_method(:chat) { |messages:, **| "Hello from #{messages.last&.dig(:role)}" }
    LLMClient.stubs(:new).returns(client)

    # Insert a user message without callbacks, then explicitly call advance_turn!
    # (mirrors Message.after_create_commit without double-triggering in tests).
    next_seq = (conversation.messages.maximum(:seq) || 0) + 1
    now = Time.current
    inserted =
      Message.insert_all!(
        [
          {
            conversation_id: conversation.id,
            space_membership_id: human.id,
            role: "user",
            content: "Hello list chain",
            visibility: "normal",
            seq: next_seq,
            created_at: now,
            updated_at: now,
          },
        ],
        returning: %w[id]
      )
    message_id = inserted.rows.dig(0, 0)
    assert message_id, "expected insert_all! to return message id"

    TurnScheduler.advance_turn!(conversation, human, message_id: message_id)

    active_round = conversation.conversation_rounds.find_by(status: "active")
    membership_debug =
      space.space_memberships.order(:position).map do |m|
        { id: m.id, kind: m.kind, status: m.status, participation: m.participation, position: m.position }
      end
    assert active_round, "expected an active round memberships=#{membership_debug.inspect}"

    queue_ids = active_round.participants.order(:position).pluck(:space_membership_id)
    assert_equal [ai1.id, ai2.id], queue_ids,
      "expected 2-slot list queue (got: #{queue_ids.inspect}) memberships=#{membership_debug.inspect}"

    run1 = conversation.conversation_runs.queued.first
    assert run1, "expected a queued run"
    assert_equal ai1.id, run1.speaker_space_membership_id
    assert_equal "auto_response", run1.kind

    # Execute the first run; this should create an assistant message and enqueue/leave a queued run for ai2.
    Conversations::RunExecutor.execute!(run1.id)

    run1.reload
    assert_equal "succeeded", run1.status, run1.error.inspect

    run2 = conversation.conversation_runs.queued.first
    runs_debug =
      conversation.conversation_runs
        .order(:created_at, :id)
        .map { |r| { id: r.id, status: r.status, kind: r.kind, speaker_id: r.speaker_space_membership_id, error: r.error, debug: r.debug } }
    assert run2, "expected second queued run after first speaker (runs=#{runs_debug.inspect})"
    assert_equal ai2.id, run2.speaker_space_membership_id, "runs=#{runs_debug.inspect}"
    assert_equal "auto_response", run2.kind

    # Execute second run; round should finish and we should have 2 assistant messages total.
    Conversations::RunExecutor.execute!(run2.id)

    assistant_ids = conversation.messages.scheduler_visible.where(role: "assistant").order(:seq, :id).pluck(:space_membership_id)
    assert_equal [ai1.id, ai2.id], assistant_ids.last(2), "assistant_ids=#{assistant_ids.inspect} runs=#{runs_debug.inspect}"

    assert_nil conversation.conversation_rounds.find_by(status: "active"), "expected round to finish (runs=#{runs_debug.inspect})"
  end
end
