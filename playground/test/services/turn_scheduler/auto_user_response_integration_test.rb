# frozen_string_literal: true

require "test_helper"

class TurnScheduler::AutoUserResponseIntegrationTest < ActiveSupport::TestCase
  setup do
    ConversationChannel.stubs(:broadcast_typing)
    ConversationChannel.stubs(:broadcast_stream_chunk)
    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_run_error_alert)

    TurnScheduler::Broadcasts.stubs(:queue_updated)

    Message.any_instance.stubs(:broadcast_create)
    Message.any_instance.stubs(:broadcast_update)
  end

  test "auto_user_response run succeeds and creates a user-role message" do
    space =
      Spaces::Playground.create!(
        name: "Auto user response integration",
        owner: users(:admin),
        reply_order: "list",
        auto_without_human_delay_ms: 0,
        user_turn_debounce_ms: 0
      )

    # Human membership (persona via freeform text, no character_id needed)
    human =
      space.space_memberships.create!(
        kind: "human",
        role: "owner",
        user: users(:admin),
        position: 0,
        persona: "Test persona",
        auto: "none",
        auto_remaining_steps: nil
      )

    ai1 =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v2),
        position: 1
      )
    space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 2
    )

    conversation = space.conversations.create!(title: "Main", kind: "root")

    # Seed history with a real user message + assistant message, so impersonate has context.
    conversation.messages.create!(space_membership: human, role: "user", content: "Seed history", generation_status: "succeeded")
    conversation.messages.create!(space_membership: ai1, role: "assistant", content: "Hi", generation_status: "succeeded")

    # Enable Auto after history exists (this is the real user flow).
    human.update!(auto: "auto", auto_remaining_steps: 1)

    # Start a new round with Auto enabled; list order should schedule the human auto speaker first.
    queue = TurnScheduler::Queries::ActivatedQueue.call(conversation: conversation)
    membership_debug =
      space.space_memberships.order(:position).map do |m|
        {
          id: m.id,
          kind: m.kind,
          auto: m.auto,
          steps: m.auto_remaining_steps,
          status: m.status,
          participation: m.participation,
          position: m.position,
        }
      end
    assert_equal [human.id, ai1.id], queue.first(2).map(&:id),
      "expected activated queue to start with the Auto human (got: #{queue.map(&:id).inspect}) memberships=#{membership_debug.inspect}"

    assert TurnScheduler.start_round!(conversation), "expected start_round! to succeed"
    run = conversation.conversation_runs.queued.first
    assert run, "expected a queued run"
    assert_equal "auto_user_response", run.kind

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) { |messages:, **| "Hello from Auto" }
    LLMClient.stubs(:new).returns(client)

    assert_difference -> { conversation.messages.where(role: "user").count }, +1 do
      Conversations::RunExecutor.execute!(run.id)
    end

    run.reload
    assert_equal "succeeded", run.status, run.error.inspect

    msg = conversation.messages.order(:seq, :id).last
    assert_equal "user", msg.role
    assert_equal human.id, msg.space_membership_id
  end
end
