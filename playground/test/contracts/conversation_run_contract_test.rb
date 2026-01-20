# frozen_string_literal: true

require "test_helper"

class ConversationRunContractTest < ActiveSupport::TestCase
  setup do
    # Keep contracts focused on Run semantics (status transitions + message effects),
    # not prompt building or Turbo streaming mechanics.
    ContextBuilder.any_instance.stubs(:build).returns([{ role: "user", content: "Hi" }])

    ConversationChannel.stubs(:broadcast_typing)
    ConversationChannel.stubs(:broadcast_stream_chunk)
    ConversationChannel.stubs(:broadcast_stream_complete)

    Messages::Broadcasts.stubs(:broadcast_auto_disabled)
    Messages::Broadcasts.stubs(:broadcast_auto_steps_updated)
    Messages::Broadcasts.stubs(:broadcast_group_queue_update)

    Message.any_instance.stubs(:broadcast_create)
    Message.any_instance.stubs(:broadcast_update)
    Message.any_instance.stubs(:broadcast_remove)

    # Avoid enqueuing background jobs as part of planning; we execute synchronously.
    Conversations::RunPlanner.stubs(:kick!).returns(true)
  end

  def stub_llm_response!(text)
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| text }

    LLMClient.stubs(:new).returns(client)
  end

  test "user_turn: plan + execute creates exactly one assistant message and marks run succeeded" do
    space = Spaces::Playground.create!(name: "Run Contract Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    human = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    user_message = conversation.messages.create!(space_membership: human, role: "user", content: "Hello")

    # Clear any auto-created runs from scheduler callbacks
    ConversationRun.where(conversation: conversation).destroy_all

    # Create a queued run manually (replaces plan_from_user_message!)
    speaker = space.space_memberships.ai_characters.first
    run = ConversationRun.create!(
      kind: "auto_response",
      conversation: conversation,
      status: "queued",
      reason: "user_message",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current,
      debug: { trigger: "user_message", user_message_id: user_message.id }
    )
    assert_equal "queued", run.status
    assert run.auto_response?

    stub_llm_response!("Assistant reply")

    assert_difference -> { conversation.messages.where(role: "assistant").count }, +1 do
      Conversations::RunExecutor.execute!(run.id)
    end

    run.reload
    assert_equal "succeeded", run.status

    assistant = conversation.messages.find_by(conversation_run_id: run.id)
    assert_not_nil assistant
    assert_equal "assistant", assistant.role
    assert_equal "Assistant reply", assistant.content
  end

  test "regenerate: plan + execute adds a swipe and does not create a new message" do
    space = Spaces::Playground.create!(name: "Regenerate Contract Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    human = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    conversation.messages.create!(space_membership: human, role: "user", content: "Hello")
    target = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "Original")

    run = Conversations::RunPlanner.plan_regenerate!(conversation: conversation, target_message: target)
    assert_equal "queued", run.status
    assert run.regenerate?

    stub_llm_response!("Regenerated")

    assert_no_difference "Message.count" do
      Conversations::RunExecutor.execute!(run.id)
    end

    run.reload
    assert_equal "succeeded", run.status

    target.reload
    assert_equal 2, target.message_swipes_count
    assert_equal "Regenerated", target.content
  end
end
