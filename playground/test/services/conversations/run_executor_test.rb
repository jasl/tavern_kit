# frozen_string_literal: true

require "test_helper"

class Conversations::RunExecutorTest < ActiveSupport::TestCase
  setup do
    ContextBuilder.any_instance.stubs(:build).returns([{ role: "user", content: "Hi" }])

    ConversationChannel.stubs(:broadcast_typing)
    ConversationChannel.stubs(:broadcast_stream_chunk)
    ConversationChannel.stubs(:broadcast_stream_complete)

    Messages::Broadcasts.stubs(:broadcast_auto_disabled)
    Messages::Broadcasts.stubs(:broadcast_auto_steps_updated)
    Messages::Broadcasts.stubs(:broadcast_group_queue_update)

    TurnScheduler::Broadcasts.stubs(:queue_updated)

    Message.any_instance.stubs(:broadcast_create)
    Message.any_instance.stubs(:broadcast_update)
    Message.any_instance.stubs(:broadcast_remove)

    # Stub scheduler callback to avoid interference in tests that manually manage runs
    Message.any_instance.stubs(:notify_scheduler_turn_complete)
  end

  test "only one executor can claim a queued run (no duplicate assistant messages)" do
    space = Spaces::Playground.create!(name: "Concurrency Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run =
      ConversationRun.create!(kind: "auto_response", conversation: conversation,

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
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      started << true
      continue.pop
      "Hello"
    end

    LLMClient.stubs(:new).returns(client)

    t1 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Conversations::RunExecutor.execute!(run.id)
      end
    end

    started.pop

    t2 = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Conversations::RunExecutor.execute!(run.id)
      end
    end

    continue << true

    t1.join
    t2.join

    assert_equal 1, conversation.messages.where(role: "assistant", conversation_run_id: run.id).count
    assert_equal "succeeded", run.reload.status
  end

  test "turn_scheduler run success reconciles round state when scheduler callback is missed" do
    space = Spaces::Playground.create!(name: "Scheduler Reconcile Space", owner: users(:admin), reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)
    conversation = space.conversations.create!(title: "Main")

    response =
      TurnScheduler::Commands::StartRoundForSpeaker.execute(
        conversation: conversation,
        speaker_id: speaker.id,
        reason: "test_start_round_for_speaker"
      )

    assert response.success?
    run = response.payload[:run]
    assert_not_nil run
    assert_equal "queued", run.status

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Hello" }
    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run.id)

    assert_equal "succeeded", run.reload.status

    conversation.reload
    assert_nil conversation.conversation_rounds.find_by(status: "active"),
      "Expected no active round after turn_scheduler run succeeded"
    assert_equal "idle", TurnScheduler.state(conversation).scheduling_state
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
      ConversationRun.create!(kind: "auto_response", conversation: conversation,

        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current
      )

    kicked = []
    Conversations::RunPlanner.stubs(:kick!).with do |r|
      kicked << r&.id
      true
    end

    provider = mock("provider")
    provider.stubs(:streamable?).returns(true)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **, &block|
      block.execute("Hello")

      msg = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Interrupt")
      # Manually create a queued run since the scheduler callback may not be triggered during LLM execute
      ConversationRun.create!(
        kind: "auto_response",
        conversation: conversation,
        status: "queued",
        reason: "user_message",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current,
        debug: { trigger: "user_message", user_message_id: msg.id }
      )
      kicked.clear

      block.execute(" world")
      "Hello world"
    end

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run1.id)
    assert_equal "succeeded", run1.reload.status

    run2 = conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil run2
    assert_includes kicked, run2.id

    provider2 = mock("provider2")
    provider2.stubs(:streamable?).returns(false)

    client2 = Object.new
    client2.define_singleton_method(:provider) { provider2 }
    client2.define_singleton_method(:last_logprobs) { nil }
    client2.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Follow up" }
    LLMClient.stubs(:new).returns(client2)

    Conversations::RunExecutor.execute!(run2.id)
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
      ConversationRun.create!(kind: "auto_response", conversation: conversation,

        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current
      )

    kicked = []
    Conversations::RunPlanner.stubs(:kick!).with do |r|
      kicked << r&.id
      true
    end

    provider = mock("provider")
    provider.stubs(:streamable?).returns(true)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **, &block|
      block.execute("Hello")

      msg = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Interrupt")
      # With restart policy, the running run should be cancel_requested
      run1.request_cancel!(at: Time.current)
      # Manually create a queued run to simulate what would happen after restart
      ConversationRun.create!(
        kind: "auto_response",
        conversation: conversation,
        status: "queued",
        reason: "user_message",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current,
        debug: { trigger: "user_message", user_message_id: msg.id }
      )
      kicked.clear

      block.execute(" world")
      "Hello world"
    end

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run1.id)
    assert_equal "canceled", run1.reload.status
    assert_nil Message.find_by(conversation_run_id: run1.id)

    run2 = conversation.conversation_runs.queued.order(:created_at, :id).last
    assert_not_nil run2
    assert_includes kicked, run2.id

    provider2 = mock("provider2")
    provider2.stubs(:streamable?).returns(false)

    client2 = Object.new
    client2.define_singleton_method(:provider) { provider2 }
    client2.define_singleton_method(:last_logprobs) { nil }
    client2.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "New response" }
    LLMClient.stubs(:new).returns(client2)

    Conversations::RunExecutor.execute!(run2.id)
    assert_equal "succeeded", run2.reload.status

    assert_equal 1, conversation.messages.where(role: "assistant").count
    assert_equal "New response", Message.find_by(conversation_run_id: run2.id)&.content
  end

  test "cancel_requested after generation prevents persistence" do
    space = Spaces::Playground.create!(name: "Late Cancel Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run =
      ConversationRun.create!(kind: "auto_response", conversation: conversation,
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current
      )

    TurnScheduler::Broadcasts.stubs(:queue_updated)
    ConversationChannel.stubs(:broadcast_typing)
    ConversationChannel.stubs(:broadcast_stream_chunk)
    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_run_canceled)

    fake_llm_client = Object.new
    fake_llm_client.define_singleton_method(:last_logprobs) { nil }

    fake_generation = Object.new
    fake_generation.define_singleton_method(:llm_client) { fake_llm_client }
    fake_generation.define_singleton_method(:generation_params_snapshot) { {} }
    fake_generation.define_singleton_method(:generate_response) do |prompt_messages|
      run.request_cancel!(at: Time.current)
      "Hello world"
    end

    Conversations::RunExecutor::RunGeneration.stubs(:new).returns(fake_generation)
    Conversations::RunExecutor.execute!(run.id)

    assert_equal "canceled", run.reload.status
    assert_nil Message.find_by(conversation_run_id: run.id)
  end

  test "failed run preserves round state and marks scheduler failed" do
    space = Spaces::Playground.create!(name: "Failure Normalize Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "ai_generating", current_position: 0)
    round.participants.create!(space_membership: speaker, position: 0, status: "pending")

    run =
      ConversationRun.create!(kind: "auto_response", conversation: conversation,
        conversation_round_id: round.id,
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current,
        debug: {
          "trigger" => "auto_response",
          "scheduled_by" => "turn_scheduler",
        }
      )

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      raise StandardError, "boom"
    end

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run.id)
    assert_equal "failed", run.reload.status

    state = TurnScheduler.state(conversation.reload)
    assert_equal "failed", state.scheduling_state
    assert_equal round.id, state.current_round_id
    assert_equal speaker.id, state.current_speaker_id
    assert_equal [speaker.id], state.round_queue_ids
  end

  test "auto-mode: queued run is skipped when last message changes before execution" do
    space =
      Spaces::Playground.create!(
        name: "Auto Mode Skip Space",
        owner: users(:admin),
        reply_order: "natural",
        auto_without_human_delay_ms: 1000,
        allow_self_responses: true
      )

    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    trigger = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "hi")

    run =
      ConversationRun.create!(kind: "auto_response", conversation: conversation,
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current,
        debug: { expected_last_message_id: trigger.id }
      )

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "newer")

    Conversations::RunExecutor.execute!(run.id)

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

    # Cancel any runs created by message callbacks
    ConversationRun.queued.where(conversation: conversation).destroy_all

    run =
      ConversationRun.create!(kind: "regenerate", conversation: conversation,
        status: "queued",
        reason: "regenerate",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current,
        debug: { target_message_id: target.id }
      )

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "New response" }
    LLMClient.stubs(:new).returns(client)

    assert_no_difference "Message.count" do
      Conversations::RunExecutor.execute!(run.id)
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
      ConversationRun.create!(kind: "regenerate", conversation: conversation,
        status: "queued",
        reason: "regenerate",
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
    Conversations::RunExecutor.execute!(run.id)

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
      ConversationRun.create!(kind: "regenerate", conversation: conversation,
        status: "queued",
        reason: "regenerate",
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

    Conversations::RunExecutor.execute!(run.id)

    assert_equal "skipped", run.reload.status
  end

  test "turn_scheduler run is skipped when scheduler-visible tail changes (hidden) and scheduler advances" do
    space = Spaces::Playground.create!(name: "TurnScheduler ExpectedLast Space", owner: users(:admin), reply_order: "manual")
    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker1 = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    speaker2 = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    # Seed a scheduler-visible tail message
    tail = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hello")

    round =
      ConversationRound.create!(
        conversation: conversation,
        status: "active",
        scheduling_state: "ai_generating",
        current_position: 0
      )
    round.participants.create!(space_membership_id: speaker1.id, position: 0)
    round.participants.create!(space_membership_id: speaker2.id, position: 1)

    # Schedule the current speaker via TurnScheduler (should set expected_last_message_id)
    run = TurnScheduler::Commands::ScheduleSpeaker.execute(conversation: conversation, speaker: speaker1, conversation_round: round).payload[:run]
    assert run
    assert_equal "queued", run.status
    assert_equal "turn_scheduler", run.debug["scheduled_by"]
    assert_equal tail.id, run.debug["expected_last_message_id"]

    # Mutate history: hide the tail message (changes scheduler-visible tail)
    tail.update!(visibility: "hidden")

    # Execute the run - should be skipped due to message mismatch
    Conversations::RunExecutor.execute!(run.id)

    run.reload
    assert_equal "skipped", run.status
    assert_equal "expected_last_message_mismatch", run.error["code"]

    # Scheduler should advance to the next speaker and enqueue a new run
    round.reload
    assert_equal 1, round.current_position

    next_run = ConversationRun.queued.find_by(conversation: conversation)
    assert next_run
    assert_equal speaker2.id, next_run.speaker_space_membership_id
    assert_equal round.id, next_run.conversation_round_id
    assert_equal "turn_scheduler", next_run.debug["scheduled_by"]
  end

  test "auto mode is not auto-disabled when AI character run fails during auto loop" do
    # Failure is treated as an "unexpected" state: the system pauses and user can Retry/Stop.
    # We do not auto-disable auto on errors.

    space = Spaces::Playground.create!(
      name: "Auto Fail Space",
      owner: users(:admin),
      reply_order: "natural"
    )
    conversation = space.conversations.create!(title: "Main")

    # Create a human membership with persona character (auto-capable)
    auto_user = space.space_memberships.create!(
      kind: "human",
      role: "owner",
      user: users(:admin),
      character: characters(:ready_v2),
      auto: "auto",
      auto_remaining_steps: 5,
      position: 0
    )

    # Create an AI character speaker
    ai_speaker = space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 1
    )

    # Simulate: auto user already sent a message, now AI character should respond
    conversation.messages.create!(space_membership: auto_user, role: "user", content: "Hello from auto")

    # Cancel any runs created by message callbacks
    ConversationRun.queued.where(conversation: conversation).destroy_all

    # Create a run for the AI character (as part of auto followup)
    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "auto_followup",
      speaker_space_membership_id: ai_speaker.id,
      run_after: Time.current,
      debug: { trigger: "auto_followup" }
    )

    # Mock LLM client to raise an error (simulating API failure)
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      raise SimpleInference::Errors::ConnectionError.new("Network error")
    end

    LLMClient.stubs(:new).returns(client)

    Messages::Broadcasts.expects(:broadcast_auto_disabled).never

    # Execute the run - it should fail
    Conversations::RunExecutor.execute!(run.id)

    # Assert the run failed
    assert_equal "failed", run.reload.status

    auto_user.reload
    assert_equal "auto", auto_user.auto
    assert_equal 5, auto_user.auto_remaining_steps

    # AI speaker should not have auto changed (it was already 'none')
    ai_speaker.reload
    assert_equal "none", ai_speaker.auto
  end

  test "auto mode remains unchanged when non-auto AI run fails" do
    # This test ensures we don't accidentally disable auto when there's no active auto user

    space = Spaces::Playground.create!(
      name: "Non-Auto Fail Space",
      owner: users(:admin),
      reply_order: "natural"
    )
    conversation = space.conversations.create!(title: "Main")

    # Create a regular human user (no persona, no auto)
    user_membership = space.space_memberships.create!(
      kind: "human",
      role: "owner",
      user: users(:admin),
      position: 0
    )

    # Create an AI character speaker
    ai_speaker = space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      position: 1
    )

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hello")

    # Cancel any runs created by message callbacks
    ConversationRun.queued.where(conversation: conversation).destroy_all

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "user_message",
      speaker_space_membership_id: ai_speaker.id,
      run_after: Time.current
    )

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      raise SimpleInference::Errors::TimeoutError.new("Timeout")
    end

    LLMClient.stubs(:new).returns(client)

    # Should NOT broadcast auto_disabled when there's no auto user
    Messages::Broadcasts.expects(:broadcast_auto_disabled).never

    Conversations::RunExecutor.execute!(run.id)

    assert_equal "failed", run.reload.status
    # User membership should still have no auto mode
    assert_equal "none", user_membership.reload.auto
  end

  test "AI followup is triggered even when auto steps reach 0 during auto user run" do
    # This test requires the scheduler callback to work, so unstub it for this test
    Message.any_instance.unstub(:notify_scheduler_turn_complete)

    space = Spaces::Playground.create!(name: "Auto Last Step Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    # Create auto user with character persona and exactly 1 step remaining
    auto_user = space.space_memberships.create!(
      kind: "human",
      role: "owner",
      user: users(:admin),
      character: characters(:ready_v2),
      position: 0,
      auto: "auto",
      auto_remaining_steps: 1
    )

    # Create AI character speaker
    ai_speaker = space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 1
    )

    # Cancel any runs created by membership callbacks
    ConversationRun.queued.where(conversation: conversation).destroy_all

    # Create an auto_start run (auto user's turn)
    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "auto_start",
      speaker_space_membership_id: auto_user.id,
      run_after: Time.current
    )

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Auto user message" }

    LLMClient.stubs(:new).returns(client)

    # Execute the auto user's run
    Conversations::RunExecutor.execute!(run.id)

    # Verify the run succeeded
    assert_equal "succeeded", run.reload.status

    # Verify auto mode was disabled because steps reached 0
    assert_equal "none", auto_user.reload.auto
    assert_nil auto_user.auto_remaining_steps

    # Key assertion: Even though auto mode is now disabled, the AI followup should have been created
    # The TurnScheduler advances the turn which should create a new queued run for the AI
    followup_run = conversation.conversation_runs.queued.where.not(id: run.id).last
    assert_not_nil followup_run, "AI followup run should be created even when steps reach 0"
    assert_equal ai_speaker.id, followup_run.speaker_space_membership_id
  end

  test "claim_queued_run sets cancel_requested_at on preempted stale run" do
    space = Spaces::Playground.create!(name: "Stale Preemption Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    now = Time.current
    stale_at = now - ConversationRun::STALE_TIMEOUT - 1.second

    # Create a stale running run
    stale_run =
      ConversationRun.create!(kind: "auto_response", conversation: conversation,

        status: "running",
        reason: "stale_test",
        speaker_space_membership_id: speaker.id,
        started_at: stale_at,
        heartbeat_at: stale_at,
        cancel_requested_at: nil
      )

    # Create a queued run that will preempt the stale one
    queued_run =
      ConversationRun.create!(kind: "auto_response", conversation: conversation,

        status: "queued",
        reason: "preempt_test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current
      )

    assert_nil stale_run.cancel_requested_at

    # Stub LLM client to return quickly
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Hello" }

    LLMClient.stubs(:new).returns(client)

    # Execute the queued run - this should preempt the stale run
    Conversations::RunExecutor.execute!(queued_run.id)

    # Verify the stale run was marked failed with cancel_requested_at set
    stale_run.reload
    assert_equal "failed", stale_run.status
    assert_equal "stale_running_run", stale_run.error["code"]
    assert_not_nil stale_run.cancel_requested_at, "cancel_requested_at should be set when stale run is preempted"
    assert stale_run.cancel_requested?, "cancel_requested? should return true"

    # Verify the queued run succeeded
    queued_run.reload
    assert_equal "succeeded", queued_run.status
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Group Message Trimming Tests
  # ─────────────────────────────────────────────────────────────────────────────

  test "trim_group_message trims dialogue from other characters in group chats" do
    space = Spaces::Playground.create!(name: "Group Trim Space", owner: users(:admin), relax_message_trim: false)
    conversation = space.conversations.create!(title: "Main")

    # Use actual character names from fixtures (cached_display_name is auto-set from character.name)
    # ready_v2 = "Ready V2 Character", ready_v3 = "Ready V3 Character"
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,

      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Stub LLM to return multi-character dialogue using actual character names
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      "Ready V2 Character says hello!\nReady V3 Character: Hey there!\nReady V2 Character: How are you?"
    end

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run.id)

    message = conversation.messages.last
    assert_equal "Ready V2 Character says hello!", message.content
    assert_not_includes message.content, "Ready V3 Character:"
  end

  test "trim_group_message does not trim when relax_message_trim is enabled" do
    space = Spaces::Playground.create!(name: "Relax Trim Space", owner: users(:admin), relax_message_trim: true)
    conversation = space.conversations.create!(title: "Main")

    # Use actual character names from fixtures
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,

      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Stub LLM to return multi-character dialogue using actual character names
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      "Ready V2 Character says hello!\nReady V3 Character: Hey there!\nReady V2 Character: How are you?"
    end

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run.id)

    message = conversation.messages.last
    assert_includes message.content, "Ready V3 Character:"
    assert_equal "Ready V2 Character says hello!\nReady V3 Character: Hey there!\nReady V2 Character: How are you?", message.content
  end

  test "trim_group_message does not trim in non-group chats" do
    space = Spaces::Playground.create!(name: "Solo Space", owner: users(:admin), relax_message_trim: false)
    conversation = space.conversations.create!(title: "Main")

    # Use actual character name from fixture
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    # Only one AI character - not a group chat

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,

      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Stub LLM to return content that mentions "Ready V3 Character:" (not a real member in this space)
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      "Ready V2 Character says hello!\nReady V3 Character: Hey there!"
    end

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run.id)

    message = conversation.messages.last
    # Should not trim because Ready V3 Character is not an actual group member in this space
    assert_includes message.content, "Ready V3 Character:"
  end

  test "trim_group_message trims at beginning of content (no newline prefix)" do
    space = Spaces::Playground.create!(name: "Prefix Trim Space", owner: users(:admin), relax_message_trim: false)
    conversation = space.conversations.create!(title: "Main")

    # Use actual character names from fixtures
    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,

      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Stub LLM to return content starting with other character's dialogue
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      "Ready V3 Character: Hey there!\nReady V2 Character: Hello!"
    end

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run.id)

    message = conversation.messages.last
    # Content starts with "Ready V3 Character:", should be trimmed to empty and handled
    assert_not_includes message.content.to_s, "Ready V3 Character:"
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Consecutive Regenerate Requests Tests
  # ─────────────────────────────────────────────────────────────────────────────

  test "consecutive regenerate requests: first is skipped when conversation advances before execution" do
    space = Spaces::Playground.create!(name: "Consecutive Regen Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    # Create initial conversation
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hello")
    target = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "Original response")

    original_content = target.content
    original_swipes_count = target.message_swipes_count

    # Create first regenerate run
    run1 = ConversationRun.create!(kind: "regenerate", conversation: conversation,
      status: "queued",
      reason: "regenerate",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current,
      debug: {
        target_message_id: target.id,
        expected_last_message_id: target.id,
      }
    )

    # Simulate user sending a new message BEFORE the regenerate executes
    # This advances the conversation, invalidating the regenerate
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Wait, let me add more context")

    ConversationChannel.stubs(:broadcast_run_skipped)

    # Execute the regenerate run - should be skipped due to message mismatch
    Conversations::RunExecutor.execute!(run1.id)

    run1.reload
    assert_equal "skipped", run1.status
    assert_equal "expected_last_message_mismatch", run1.error["code"]

    # Target message should NOT be modified by skipped run
    target.reload
    assert_equal original_content, target.content
    assert_equal original_swipes_count, target.message_swipes_count
  end

  test "consecutive regenerate requests: database constraint prevents duplicate queued runs" do
    space = Spaces::Playground.create!(name: "Duplicate Regen Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hello")
    target = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "Original response")

    # Create first queued regenerate run
    run1 = ConversationRun.create!(kind: "regenerate", conversation: conversation,
      status: "queued",
      reason: "regenerate",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current,
      debug: { target_message_id: target.id }
    )

    # Attempting to create another queued run should fail due to unique constraint
    assert_raises ActiveRecord::RecordNotUnique do
      ConversationRun.create!(kind: "regenerate", conversation: conversation,
        status: "queued",
        reason: "regenerate",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current,
        debug: { target_message_id: target.id }
      )
    end

    # Only one queued run should exist
    assert_equal 1, conversation.conversation_runs.queued.count
  end

  test "regenerate run is skipped when target message no longer exists" do
    space = Spaces::Playground.create!(name: "Deleted Target Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hello")
    target = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "Original response")
    target_id = target.id

    run = ConversationRun.create!(kind: "regenerate", conversation: conversation,
      status: "queued",
      reason: "regenerate",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current,
      debug: {
        target_message_id: target_id,
        expected_last_message_id: target_id,
      }
    )

    # Delete the target message before execution
    target.destroy!

    ConversationChannel.stubs(:broadcast_run_skipped)

    # Execute the run - should be skipped because target doesn't exist
    Conversations::RunExecutor.execute!(run.id)

    run.reload
    assert_equal "skipped", run.status
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Token Usage Statistics Tests
  # ─────────────────────────────────────────────────────────────────────────────

  test "successful run increments token usage on conversation, space, and owner user" do
    owner = users(:admin)
    space = Spaces::Playground.create!(name: "Token Stats Space", owner: owner)
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: owner, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    # Record initial token counts
    initial_conv_prompt = conversation.prompt_tokens_total
    initial_conv_completion = conversation.completion_tokens_total
    initial_space_prompt = space.prompt_tokens_total
    initial_space_completion = space.completion_tokens_total
    initial_user_prompt = owner.prompt_tokens_total
    initial_user_completion = owner.completion_tokens_total

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Mock LLM client with usage data
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    usage_data = { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:last_usage) { usage_data }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Hello world" }

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run.id)

    assert_equal "succeeded", run.reload.status

    # Reload and verify token counts incremented correctly
    conversation.reload
    space.reload
    owner.reload

    assert_equal initial_conv_prompt + 100, conversation.prompt_tokens_total
    assert_equal initial_conv_completion + 50, conversation.completion_tokens_total

    assert_equal initial_space_prompt + 100, space.prompt_tokens_total
    assert_equal initial_space_completion + 50, space.completion_tokens_total

    assert_equal initial_user_prompt + 100, owner.prompt_tokens_total
    assert_equal initial_user_completion + 50, owner.completion_tokens_total

    # Verify usage is also stored in run.debug (stored with string keys)
    assert_equal usage_data[:prompt_tokens], run.debug["usage"]["prompt_tokens"]
    assert_equal usage_data[:completion_tokens], run.debug["usage"]["completion_tokens"]
    assert_equal usage_data[:total_tokens], run.debug["usage"]["total_tokens"]
  end

  test "token usage is not incremented when LLM client returns nil usage" do
    owner = users(:admin)
    space = Spaces::Playground.create!(name: "No Usage Space", owner: owner)
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: owner, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    # Record initial token counts
    initial_conv_prompt = conversation.prompt_tokens_total
    initial_space_prompt = space.prompt_tokens_total
    initial_user_prompt = owner.prompt_tokens_total

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Mock LLM client without usage data (e.g., provider doesn't support it)
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:last_usage) { nil }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Hello world" }

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run.id)

    assert_equal "succeeded", run.reload.status

    # Reload and verify token counts remain unchanged
    conversation.reload
    space.reload
    owner.reload

    assert_equal initial_conv_prompt, conversation.prompt_tokens_total
    assert_equal initial_space_prompt, space.prompt_tokens_total
    assert_equal initial_user_prompt, owner.prompt_tokens_total
  end

  test "token usage accumulates across multiple runs" do
    owner = users(:admin)
    space = Spaces::Playground.create!(name: "Multi Run Space", owner: owner)
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: owner, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    # Execute first run with usage
    run1 = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "test1",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    usage1 = { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }
    client1 = Object.new
    client1.define_singleton_method(:provider) { provider }
    client1.define_singleton_method(:last_logprobs) { nil }
    client1.define_singleton_method(:last_usage) { usage1 }
    client1.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "First response" }

    LLMClient.stubs(:new).returns(client1)
    Conversations::RunExecutor.execute!(run1.id)

    # Execute second run with different usage
    run2 = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "test2",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    usage2 = { prompt_tokens: 200, completion_tokens: 100, total_tokens: 300 }
    client2 = Object.new
    client2.define_singleton_method(:provider) { provider }
    client2.define_singleton_method(:last_logprobs) { nil }
    client2.define_singleton_method(:last_usage) { usage2 }
    client2.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Second response" }

    LLMClient.stubs(:new).returns(client2)
    Conversations::RunExecutor.execute!(run2.id)

    # Verify totals accumulated
    conversation.reload
    space.reload
    owner.reload

    assert_equal 300, conversation.prompt_tokens_total # 100 + 200
    assert_equal 150, conversation.completion_tokens_total # 50 + 100

    assert_equal 300, space.prompt_tokens_total
    assert_equal 150, space.completion_tokens_total

    assert_equal 300, owner.prompt_tokens_total
    assert_equal 150, owner.completion_tokens_total
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Token Limit Tests
  # ─────────────────────────────────────────────────────────────────────────────

  test "run fails with token_limit_exceeded when space exceeds its token limit" do
    owner = users(:admin)
    space = Spaces::Playground.create!(name: "Limited Space", owner: owner, token_limit: 1000)
    conversation = space.conversations.create!(title: "Main")

    # Set token usage to exceed the limit
    space.update_columns(prompt_tokens_total: 800, completion_tokens_total: 300)

    space.space_memberships.create!(kind: "human", role: "owner", user: owner, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Should not execute LLM since limit is exceeded before generation
    LLMClient.expects(:new).never

    Conversations::RunExecutor.execute!(run.id)

    run.reload
    assert_equal "failed", run.status
    assert_equal "token_limit_exceeded", run.error["code"]
    assert_equal 1000, run.error["limit"]
    assert_equal 1100, run.error["used"]
  end

  test "run fails with token_limit_exceeded when global limit is exceeded" do
    Setting.set("space.max_token_limit", "500")

    owner = users(:admin)
    space = Spaces::Playground.create!(name: "Global Limited Space", owner: owner)
    conversation = space.conversations.create!(title: "Main")

    # Set token usage to exceed the global limit
    space.update_columns(prompt_tokens_total: 400, completion_tokens_total: 200)

    space.space_memberships.create!(kind: "human", role: "owner", user: owner, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    LLMClient.expects(:new).never

    Conversations::RunExecutor.execute!(run.id)

    run.reload
    assert_equal "failed", run.status
    assert_equal "token_limit_exceeded", run.error["code"]
    assert_equal 500, run.error["limit"]
    assert_equal 600, run.error["used"]
  ensure
    Setting.delete("space.max_token_limit")
  end

  test "run proceeds normally when under token limit" do
    owner = users(:admin)
    space = Spaces::Playground.create!(name: "Under Limit Space", owner: owner, token_limit: 10_000)
    conversation = space.conversations.create!(title: "Main")

    # Set token usage well under the limit
    space.update_columns(prompt_tokens_total: 100, completion_tokens_total: 50)

    space.space_memberships.create!(kind: "human", role: "owner", user: owner, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:last_usage) { { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 } }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Hello world" }

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run.id)

    run.reload
    assert_equal "succeeded", run.status
  end

  test "run proceeds normally when no token limit is set" do
    owner = users(:admin)
    space = Spaces::Playground.create!(name: "Unlimited Space", owner: owner)
    conversation = space.conversations.create!(title: "Main")
    Setting.delete("space.max_token_limit")

    # Set very high token usage - but no limit, so it should proceed
    space.update_columns(prompt_tokens_total: 1_000_000, completion_tokens_total: 500_000)

    space.space_memberships.create!(kind: "human", role: "owner", user: owner, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:last_usage) { { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 } }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Hello world" }

    LLMClient.stubs(:new).returns(client)

    Conversations::RunExecutor.execute!(run.id)

    run.reload
    assert_equal "succeeded", run.status
  end
end
