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
    Message::Broadcasts.stubs(:broadcast_group_queue_update)

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
    client.define_singleton_method(:last_logprobs) { nil }
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
    client.define_singleton_method(:last_logprobs) { nil }
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
    client2.define_singleton_method(:last_logprobs) { nil }
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
    client.define_singleton_method(:last_logprobs) { nil }
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
    client2.define_singleton_method(:last_logprobs) { nil }
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
    client.define_singleton_method(:last_logprobs) { nil }
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

  test "copilot mode is disabled when AI character run fails during copilot loop" do
    # This test verifies the fix for: Full Copilot mode getting stuck when AI character's
    # run fails. Before the fix, copilot_mode would remain "full" but no new run would be
    # created, causing the conversation to get stuck.

    space = Spaces::Playground.create!(
      name: "Copilot Fail Space",
      owner: users(:admin),
      reply_order: "natural"
    )
    conversation = space.conversations.create!(title: "Main")

    # Create a human membership with persona character (copilot-capable)
    copilot_user = space.space_memberships.create!(
      kind: "human",
      role: "owner",
      user: users(:admin),
      character: characters(:ready_v2),
      copilot_mode: "full",
      copilot_remaining_steps: 5,
      position: 0
    )

    # Create an AI character speaker
    ai_speaker = space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 1
    )

    # Simulate: copilot user already sent a message, now AI character should respond
    conversation.messages.create!(space_membership: copilot_user, role: "user", content: "Hello from copilot")

    # Create a run for the AI character (as part of copilot followup)
    run = conversation.conversation_runs.create!(
      kind: "user_turn",
      status: "queued",
      reason: "copilot_followup",
      speaker_space_membership_id: ai_speaker.id,
      run_after: Time.current,
      debug: { trigger: "copilot_followup" }
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

    # Verify copilot_disabled is broadcast to the copilot user (not the AI speaker)
    Message::Broadcasts.expects(:broadcast_copilot_disabled).with(
      copilot_user,
      error: "Network error while contacting the LLM provider. Please try again."
    ).once

    # Execute the run - it should fail
    Conversation::RunExecutor.execute!(run.id)

    # Assert the run failed
    assert_equal "failed", run.reload.status

    # THE KEY ASSERTION: copilot mode should be disabled for the copilot user
    copilot_user.reload
    assert_equal "none", copilot_user.copilot_mode,
                 "Copilot mode should be disabled when AI character's run fails"

    # AI speaker should not have copilot_mode changed (it was already 'none')
    ai_speaker.reload
    assert_equal "none", ai_speaker.copilot_mode
  end

  test "copilot mode remains unchanged when non-copilot AI run fails" do
    # This test ensures we don't accidentally disable copilot when there's no active copilot user

    space = Spaces::Playground.create!(
      name: "Non-Copilot Fail Space",
      owner: users(:admin),
      reply_order: "natural"
    )
    conversation = space.conversations.create!(title: "Main")

    # Create a regular human user (no persona, no copilot)
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

    run = conversation.conversation_runs.create!(
      kind: "user_turn",
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

    # Should NOT broadcast copilot_disabled when there's no copilot user
    Message::Broadcasts.expects(:broadcast_copilot_disabled).never

    Conversation::RunExecutor.execute!(run.id)

    assert_equal "failed", run.reload.status
    # User membership should still have no copilot mode
    assert_equal "none", user_membership.reload.copilot_mode
  end

  test "AI followup is triggered even when copilot steps reach 0 during copilot user run" do
    space = Spaces::Playground.create!(name: "Copilot Last Step Space", owner: users(:admin), reply_order: "natural")
    conversation = space.conversations.create!(title: "Main")

    # Create copilot user with character persona and exactly 1 step remaining
    copilot_user = space.space_memberships.create!(
      kind: "human",
      role: "owner",
      user: users(:admin),
      character: characters(:ready_v2),
      position: 0,
      copilot_mode: "full",
      copilot_remaining_steps: 1
    )

    # Create AI character speaker
    ai_speaker = space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      position: 1
    )

    # Create a copilot_start run (copilot user's turn)
    run = conversation.conversation_runs.create!(
      kind: "user_turn",
      status: "queued",
      reason: "copilot_start",
      speaker_space_membership_id: copilot_user.id,
      run_after: Time.current
    )

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Copilot user message" }

    LLMClient.stubs(:new).returns(client)

    # Execute the copilot user's run
    Conversation::RunExecutor.execute!(run.id)

    # Verify the run succeeded
    assert_equal "succeeded", run.reload.status

    # Verify copilot mode was disabled because steps reached 0
    assert_equal "none", copilot_user.reload.copilot_mode
    assert_equal 0, copilot_user.copilot_remaining_steps

    # Key assertion: Even though copilot mode is now disabled, the AI followup should have been created
    followup_run = conversation.conversation_runs.where(reason: "copilot_followup").last
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
      conversation.conversation_runs.create!(
        kind: "user_turn",
        status: "running",
        reason: "stale_test",
        speaker_space_membership_id: speaker.id,
        started_at: stale_at,
        heartbeat_at: stale_at,
        cancel_requested_at: nil
      )

    # Create a queued run that will preempt the stale one
    queued_run =
      conversation.conversation_runs.create!(
        kind: "user_turn",
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
    Conversation::RunExecutor.execute!(queued_run.id)

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

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1, cached_display_name: "Alice")
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2, cached_display_name: "Bob")

    run = conversation.conversation_runs.create!(
      kind: "user_turn",
      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Stub LLM to return multi-character dialogue
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      "Alice says hello!\nBob: Hey there!\nAlice: How are you?"
    end

    LLMClient.stubs(:new).returns(client)

    Conversation::RunExecutor.execute!(run.id)

    message = conversation.messages.last
    assert_equal "Alice says hello!", message.content
    assert_not_includes message.content, "Bob:"
  end

  test "trim_group_message does not trim when relax_message_trim is enabled" do
    space = Spaces::Playground.create!(name: "Relax Trim Space", owner: users(:admin), relax_message_trim: true)
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1, cached_display_name: "Alice")
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2, cached_display_name: "Bob")

    run = conversation.conversation_runs.create!(
      kind: "user_turn",
      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Stub LLM to return multi-character dialogue
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      "Alice says hello!\nBob: Hey there!\nAlice: How are you?"
    end

    LLMClient.stubs(:new).returns(client)

    Conversation::RunExecutor.execute!(run.id)

    message = conversation.messages.last
    assert_includes message.content, "Bob:"
    assert_equal "Alice says hello!\nBob: Hey there!\nAlice: How are you?", message.content
  end

  test "trim_group_message does not trim in non-group chats" do
    space = Spaces::Playground.create!(name: "Solo Space", owner: users(:admin), relax_message_trim: false)
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1, cached_display_name: "Alice")
    # Only one AI character - not a group chat

    run = conversation.conversation_runs.create!(
      kind: "user_turn",
      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Stub LLM to return content that mentions "Bob:" (not a real member)
    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) do |messages:, max_tokens: nil, **|
      "Alice says hello!\nBob: Hey there!"
    end

    LLMClient.stubs(:new).returns(client)

    Conversation::RunExecutor.execute!(run.id)

    message = conversation.messages.last
    # Should not trim because Bob is not an actual group member
    assert_includes message.content, "Bob:"
  end

  test "trim_group_message trims at beginning of content (no newline prefix)" do
    space = Spaces::Playground.create!(name: "Prefix Trim Space", owner: users(:admin), relax_message_trim: false)
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1, cached_display_name: "Alice")
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2, cached_display_name: "Bob")

    run = conversation.conversation_runs.create!(
      kind: "user_turn",
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
      "Bob: Hey there!\nAlice: Hello!"
    end

    LLMClient.stubs(:new).returns(client)

    Conversation::RunExecutor.execute!(run.id)

    message = conversation.messages.last
    # Content starts with "Bob:", should be trimmed to empty and handled
    assert_not_includes message.content.to_s, "Bob:"
  end
end
