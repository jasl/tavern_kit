# frozen_string_literal: true

require "test_helper"

class Conversation::RunExecutorTest < ActiveSupport::TestCase
  setup do
    ContextBuilder.any_instance.stubs(:build).returns([{ role: "user", content: "Hi" }])

    ConversationChannel.stubs(:broadcast_typing)
    ConversationChannel.stubs(:broadcast_stream_chunk)
    ConversationChannel.stubs(:broadcast_stream_complete)

    Message::Broadcasts.stubs(:broadcast_copilot_disabled)
    Message::Broadcasts.stubs(:broadcast_copilot_steps_updated)

    Message.any_instance.stubs(:broadcast_create)
    Message.any_instance.stubs(:broadcast_update)
    Message.any_instance.stubs(:broadcast_remove)
  end

  test "only one executor can claim a queued run (no duplicate assistant messages)" do
    space = Spaces::Playground.create!(name: "Concurrency Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run =
      conversation.conversation_runs.create!(
        kind: "user_turn",
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current
      )

    started = Queue.new
    continue = Queue.new

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      started << true
      continue.pop
      "Hello"
    end

    LLMClient.stubs(:new).returns(client)

    t1 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Conversation::RunExecutor.execute!(run.id)
      end
    end

    started.pop

    t2 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Conversation::RunExecutor.execute!(run.id)
      end
    end

    continue << true

    t1.join
    t2.join

    assert_equal 1, conversation.messages.where(role: "assistant", conversation_run_id: run.id).count
    assert_equal "succeeded", run.reload.status
  end

  test "queue: user input during generation creates queued run and it is kicked after running succeeds" do
    space =
      Spaces::Playground.create!(
        name: "Queue Followup Space",
        owner: users(:admin),
        reply_order: "natural",
        during_generation_user_input_policy: "queue",
        user_turn_debounce_ms: 0
      )

    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run1 =
      conversation.conversation_runs.create!(
        kind: "user_turn",
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current
      )

    kicked = []
    Conversation::RunPlanner.stubs(:kick!).with do |r|
      kicked << r&.id
      true
    end

    provider = mock("provider")
    provider.stubs(:streamable?).returns(true)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **, &block|
      block.call("Hello")

      msg = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Interrupt")
      Conversation::RunPlanner.plan_from_user_message!(conversation: conversation, user_message: msg)
      kicked.clear

      block.call(" world")
      "Hello world"
    end

    LLMClient.stubs(:new).returns(client)

    Conversation::RunExecutor.execute!(run1.id)
    assert_equal "succeeded", run1.reload.status

    run2 = conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil run2
    assert_includes kicked, run2.id

    provider2 = mock("provider2")
    provider2.stubs(:streamable?).returns(false)

    client2 = Object.new
    client2.define_singleton_method(:provider) { provider2 }
    client2.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Follow up" }
    LLMClient.stubs(:new).returns(client2)

    Conversation::RunExecutor.execute!(run2.id)
    assert_equal "succeeded", run2.reload.status

    assert_equal 2, conversation.messages.where(role: "assistant").count
    assert_equal "Hello world", Message.find_by(conversation_run_id: run1.id)&.content
    assert_equal "Follow up", Message.find_by(conversation_run_id: run2.id)&.content
  end

  test "restart: cancel_requested aborts running run and queued run executes without pollution" do
    space =
      Spaces::Playground.create!(
        name: "Restart Space",
        owner: users(:admin),
        reply_order: "natural",
        during_generation_user_input_policy: "restart",
        user_turn_debounce_ms: 0
      )

    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run1 =
      conversation.conversation_runs.create!(
        kind: "user_turn",
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current
      )

    kicked = []
    Conversation::RunPlanner.stubs(:kick!).with do |r|
      kicked << r&.id
      true
    end

    provider = mock("provider")
    provider.stubs(:streamable?).returns(true)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **, &block|
      block.call("Hello")

      msg = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Interrupt")
      Conversation::RunPlanner.plan_from_user_message!(conversation: conversation, user_message: msg)
      kicked.clear

      block.call(" world")
      "Hello world"
    end

    LLMClient.stubs(:new).returns(client)

    Conversation::RunExecutor.execute!(run1.id)
    assert_equal "canceled", run1.reload.status
    assert_nil Message.find_by(conversation_run_id: run1.id)

    run2 = conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil run2
    assert_includes kicked, run2.id

    provider2 = mock("provider2")
    provider2.stubs(:streamable?).returns(false)

    client2 = Object.new
    client2.define_singleton_method(:provider) { provider2 }
    client2.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "New response" }
    LLMClient.stubs(:new).returns(client2)

    Conversation::RunExecutor.execute!(run2.id)
    assert_equal "succeeded", run2.reload.status

    assert_equal 1, conversation.messages.where(role: "assistant").count
    assert_equal "New response", Message.find_by(conversation_run_id: run2.id)&.content
  end

  test "auto-mode: queued run is skipped when last message changes before execution" do
    space =
      Spaces::Playground.create!(
        name: "Auto Mode Skip Space",
        owner: users(:admin),
        reply_order: "natural",
        auto_mode_enabled: true,
        auto_mode_delay_ms: 1000,
        allow_self_responses: true
      )

    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    trigger = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "hi")

    run =
      conversation.conversation_runs.create!(
        kind: "auto_mode",
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current,
        debug: { expected_last_message_id: trigger.id }
      )

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "newer")

    Conversation::RunExecutor.execute!(run.id)

    run.reload
    assert_equal "skipped", run.status
    assert_equal 0, Message.where(conversation_run_id: run.id).count
  end

  test "regenerate adds a swipe to the target message and does not enqueue followups" do
    space = Spaces::Playground.create!(name: "Regenerate Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hello")
    target = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "Original response")
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Follow up question")

    run =
      conversation.conversation_runs.create!(
        kind: "regenerate",
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current,
        debug: { target_message_id: target.id }
      )

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "New response" }
    LLMClient.stubs(:new).returns(client)

    assert_no_difference "Message.count" do
      Conversation::RunExecutor.execute!(run.id)
    end

    assert_equal "succeeded", run.reload.status

    target.reload
    assert_equal 2, target.message_swipes_count
    assert_equal "New response", target.content
    assert_equal 0, conversation.conversation_runs.queued.where.not(id: run.id).count
  end

  test "regenerate is skipped when new message arrives before execution" do
    space = Spaces::Playground.create!(name: "Regenerate Race Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    # Create initial conversation: user message -> assistant message (target for regenerate)
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hello")
    target = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "Original response")

    original_content = target.content
    original_swipes_count = target.message_swipes_count

    # Plan regenerate (queued) with expected_last_message_id = target.id
    run =
      conversation.conversation_runs.create!(
        kind: "regenerate",
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current,
        debug: {
          target_message_id: target.id,
          expected_last_message_id: target.id,
        }
      )

    # Simulate race condition: user sends new message before regenerate executes
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Actually, never mind")

    # Stub the broadcast to verify it's called
    ConversationChannel.stubs(:broadcast_run_skipped)

    # Execute the run - should be skipped due to message mismatch
    Conversation::RunExecutor.execute!(run.id)

    # Assert run was skipped
    run.reload
    assert_equal "skipped", run.status
    assert_equal "expected_last_message_mismatch", run.error["code"]

    # Assert target message was NOT modified
    target.reload
    assert_equal original_content, target.content
    assert_equal original_swipes_count, target.message_swipes_count

    # Assert no new messages were created by this run
    assert_equal 0, Message.where(conversation_run_id: run.id).count
  end

  test "regenerate broadcasts run_skipped notification when skipped due to race condition" do
    space = Spaces::Playground.create!(name: "Regenerate Broadcast Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hello")
    target = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "Original response")

    run =
      conversation.conversation_runs.create!(
        kind: "regenerate",
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current,
        debug: {
          target_message_id: target.id,
          expected_last_message_id: target.id,
        }
      )

    # New message arrives, invalidating regenerate
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "New message")

    # Expect broadcast_run_skipped to be called with correct params
    ConversationChannel.expects(:broadcast_run_skipped).with(
      conversation,
      reason: "message_mismatch",
      message: "Conversation advanced; regenerate skipped."
    ).once

    Conversation::RunExecutor.execute!(run.id)

    assert_equal "skipped", run.reload.status
  end
end
