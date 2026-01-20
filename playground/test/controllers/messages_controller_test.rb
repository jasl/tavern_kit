# frozen_string_literal: true

require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :admin
    @conversation = conversations(:general_main)
  end

  test "create creates a user message with next seq and enqueues a run" do
    assert_difference "Message.count", 1 do
      assert_difference "ConversationRun.count", 1 do
        assert_enqueued_with(job: ConversationRunJob) do
          post conversation_messages_url(@conversation), params: { message: { content: "New message" } }
        end
      end
    end

    msg = @conversation.messages.order(:seq, :id).last
    assert_equal "user", msg.role
    assert_equal "New message", msg.content
    assert_equal space_memberships(:admin_in_general).id, msg.space_membership_id
    assert_equal 3, msg.seq

    run = ConversationRun.order(:created_at, :id).last
    assert_equal "queued", run.status
    assert run.auto_response?
    assert_equal space_memberships(:character_in_general).id, run.speaker_space_membership_id

    assert_redirected_to conversation_url(@conversation, anchor: "message_#{msg.id}")
  end

  test "create triggers the run job and creates an assistant reply" do
    ConversationChannel.stubs(:broadcast_typing)
    ConversationChannel.stubs(:broadcast_stream_chunk)
    ConversationChannel.stubs(:broadcast_stream_complete)

    Message.any_instance.stubs(:broadcast_create)
    Message.any_instance.stubs(:broadcast_update)

    provider = mock("provider")
    provider.stubs(:streamable?).returns(false)

    client = Object.new
    client.define_singleton_method(:provider) { provider }
    client.define_singleton_method(:last_logprobs) { nil }
    client.define_singleton_method(:chat) { |messages:, max_tokens: nil, **| "Assistant reply" }

    LLMClient.stubs(:new).returns(client)

    assert_difference "Message.where(role: 'assistant').count", 1 do
      perform_enqueued_jobs do
        post conversation_messages_url(@conversation), params: { message: { content: "New message" } }
      end
    end

    reply = @conversation.messages.where(role: "assistant").order(:seq, :id).last
    assert_equal "Assistant reply", reply.content

    run = ConversationRun.order(:created_at, :id).last
    assert_equal "succeeded", run.status
  end

  test "create with blank content does not create a message" do
    assert_no_difference "Message.count" do
      post conversation_messages_url(@conversation), params: { message: { content: "" } }
    end

    assert_redirected_to conversation_url(@conversation)
  end

  test "create resets blocked (failed) round by stopping auto without human and auto before accepting user input" do
    ConversationChannel.stubs(:broadcast_to)
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    space = Spaces::Playground.create!(name: "Blocked Turn Reset Space", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main")

    persona =
      Character.create!(
        name: "Persona",
        personality: "Persona",
        data: { "name" => "Persona" },
        spec_version: 2,
        file_sha256: "persona_#{SecureRandom.hex(8)}",
        status: "ready",
        visibility: "private"
      )

    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    user_membership.update!(character: persona, auto: "auto", auto_remaining_steps: 4)

    conversation.start_auto_without_human!(rounds: 3)

    ai1 = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    ai2 = space.space_memberships.find_by!(character: characters(:ready_v3), kind: "character")

    blocked_round =
      ConversationRound.create!(
        conversation: conversation,
        status: "active",
        scheduling_state: "failed",
        current_position: 0
      )
    blocked_round.participants.create!(space_membership: ai1, position: 0, status: "pending")
    blocked_round.participants.create!(space_membership: ai2, position: 1, status: "pending")

    assert TurnScheduler.state(conversation).failed?
    assert conversation.auto_without_human_enabled?
    assert user_membership.auto_enabled?

    assert_difference "Message.count", 1 do
      assert_difference "ConversationRun.count", 1 do
        assert_enqueued_with(job: ConversationRunJob) do
          post conversation_messages_url(conversation), params: { message: { content: "Reset please" } }
        end
      end
    end

    conversation.reload
    user_membership.reload

    assert_not conversation.auto_without_human_enabled?
    assert user_membership.auto_none?
    assert_nil user_membership.auto_remaining_steps

    blocked_round.reload
    assert_equal "canceled", blocked_round.status
    assert_equal "stop_round", blocked_round.ended_reason

    # Message after_create_commit should start a new round and enqueue a run.
    state = TurnScheduler.state(conversation)
    assert_not state.idle?
    assert_not state.failed?
    assert_not_nil state.current_round_id
    assert_not_equal blocked_round.id, state.current_round_id

    queued = conversation.conversation_runs.queued.first
    assert_not_nil queued
    assert_equal state.current_round_id, queued.conversation_round_id
    assert_equal "turn_scheduler", queued.debug["scheduled_by"]

    assert_redirected_to conversation_url(conversation, anchor: "message_#{Message.order(:id).last.id}")
  end

  test "index returns not_found when user is not a member of the space" do
    # Create a new space that the admin user is NOT a member of
    other_user = users(:member)
    other_space = Spaces::Playground.create!(name: "Private Space", owner: other_user)
    other_space.space_memberships.grant_to(other_user, role: "owner")
    other_space.space_memberships.grant_to(characters(:ready_v2))
    other_conversation = other_space.conversations.create!(title: "Private Chat")

    # Admin should not be able to access messages in this space
    # Returns 404 to avoid revealing resource existence (security best practice)
    get conversation_messages_url(other_conversation)

    assert_response :not_found
  end

  test "show returns not_found when user is not a member of the space" do
    other_user = users(:member)
    character = characters(:ready_v2)
    other_space = Spaces::Playground.create!(name: "Private Space", owner: other_user)
    other_space.space_memberships.grant_to(other_user, role: "owner")
    other_space.space_memberships.grant_to(character)
    character_membership = other_space.space_memberships.find_by(character: character)
    other_conversation = other_space.conversations.create!(title: "Private Chat")
    other_message = other_conversation.messages.create!(
      space_membership: character_membership,
      role: "assistant",
      content: "Secret message"
    )

    # Returns 404 to avoid revealing resource existence (security best practice)
    get conversation_message_url(other_conversation, other_message)

    assert_response :not_found
  end

  test "edit on non-tail message returns unprocessable_entity" do
    user_membership = space_memberships(:admin_in_general)

    # Create two messages - first one will be non-tail
    first_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "First message"
    )
    _second_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Second message"
    )

    # Try to get the edit form for the first (non-tail) message
    get edit_conversation_message_url(@conversation, first_message)

    assert_redirected_to conversation_url(@conversation)
    assert_match(/cannot edit/i, flash[:alert])
  end

  test "inline_edit on non-tail message returns unprocessable_entity" do
    user_membership = space_memberships(:admin_in_general)

    # Create two messages - first one will be non-tail
    first_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "First message"
    )
    _second_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Second message"
    )

    # Try to get the inline edit form for the first (non-tail) message
    get inline_edit_conversation_message_url(@conversation, first_message)

    assert_redirected_to conversation_url(@conversation)
    assert_match(/cannot edit/i, flash[:alert])
  end

  test "inline_edit on tail message is allowed" do
    user_membership = space_memberships(:admin_in_general)

    # Create a message that will be the last one
    last_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Last message"
    )

    get inline_edit_conversation_message_url(@conversation, last_message)

    assert_response :success
  end

  test "update on non-tail message returns unprocessable_entity" do
    user_membership = space_memberships(:admin_in_general)

    # Create two messages - first one will be non-tail
    first_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "First message"
    )
    _second_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Second message"
    )

    # Try to update the first (non-tail) message
    patch conversation_message_url(@conversation, first_message),
          params: { message: { content: "Edited content" } }

    assert_redirected_to conversation_url(@conversation)
    assert_match(/cannot edit/i, flash[:alert])

    # Verify content was NOT changed
    first_message.reload
    assert_equal "First message", first_message.content
  end

  test "destroy on non-tail message hides the message (soft delete)" do
    user_membership = space_memberships(:admin_in_general)

    # Create two messages - first one will be non-tail
    first_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "First message"
    )
    second_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Second message"
    )

    # Try to delete the first (non-tail) message
    assert_no_difference "Message.count" do
      delete conversation_message_url(@conversation, first_message)
    end

    assert_redirected_to conversation_url(@conversation)

    first_message.reload
    second_message.reload
    assert first_message.visibility_hidden?
    assert second_message.visibility_normal?
    assert_nil @conversation.messages.ui_visible.find_by(id: first_message.id)
  end

  test "update on tail message is allowed" do
    user_membership = space_memberships(:admin_in_general)

    # Create a message that will be the last one
    last_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Last message"
    )

    patch conversation_message_url(@conversation, last_message),
          params: { message: { content: "Edited last message" } }

    last_message.reload
    assert_equal "Edited last message", last_message.content
  end

  test "destroy on tail message is allowed" do
    user_membership = space_memberships(:admin_in_general)

    # Create a message that will be the last one
    last_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Last message"
    )

    assert_no_difference "Message.count" do
      delete conversation_message_url(@conversation, last_message)
    end

    last_message.reload
    assert last_message.visibility_hidden?
  end

  test "destroy via turbo_stream hides message (no template error)" do
    user_membership = space_memberships(:admin_in_general)

    message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Turbo delete"
    )

    assert_no_difference "Message.count" do
      delete conversation_message_url(@conversation, message), as: :turbo_stream
    end

    assert_response :success

    message.reload
    assert message.visibility_hidden?
  end

  test "destroy cancels queued run triggered by the deleted message" do
    user_membership = space_memberships(:admin_in_general)

    # Create a message and trigger a queued run
    message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Message to delete"
    )

    # Clear any auto-created runs from scheduler callbacks
    ConversationRun.where(conversation: @conversation).destroy_all

    # Create a run simulating being triggered by this message
    speaker = @conversation.space.space_memberships.ai_characters.first
    queued_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      status: "queued",
      reason: "user_message",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current,
      debug: { trigger: "user_message", user_message_id: message.id }
    )

    assert_equal "queued", queued_run.status
    assert queued_run.auto_response?
    assert_equal "user_message", queued_run.debug["trigger"]
    assert_equal message.id, queued_run.debug["user_message_id"]

    # Delete the message
    assert_no_difference "Message.count" do
      delete conversation_message_url(@conversation, message)
    end

    # Verify the queued run was canceled
    queued_run.reload
    assert_equal "canceled", queued_run.status
    assert_not_nil queued_run.finished_at

    message.reload
    assert message.visibility_hidden?
  end

  test "destroy cancels queued run triggered by the most recent user message" do
    user_membership = space_memberships(:admin_in_general)

    # Create a message
    message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Test message"
    )

    # Clear any auto-created runs from scheduler callbacks
    ConversationRun.where(conversation: @conversation).destroy_all

    # Create a run simulating being triggered by this message
    speaker = @conversation.space.space_memberships.ai_characters.first
    queued_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      status: "queued",
      reason: "user_message",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current,
      debug: { trigger: "user_message", user_message_id: message.id }
    )

    assert_equal "queued", queued_run.status
    assert_equal message.id, queued_run.debug["user_message_id"]

    # Delete the message
    assert_no_difference "Message.count" do
      delete conversation_message_url(@conversation, message)
    end

    # Verify the queued run was canceled (it was triggered by the deleted message)
    queued_run.reload
    assert_equal "canceled", queued_run.status
    assert_not_nil queued_run.finished_at

    message.reload
    assert message.visibility_hidden?
  end

  test "destroy does not cancel queued run with different trigger type" do
    space = Spaces::Playground.create!(name: "Force Talk Test", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Test", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    # Create a user message
    message = conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "User message"
    )

    # Create a force_talk run (not triggered by user_message)
    force_talk_run = Conversations::RunPlanner.plan_force_talk!(
      conversation: conversation,
      speaker_space_membership_id: ai_membership.id
    )

    assert force_talk_run, "Expected a queued run to be created"
    assert_equal "queued", force_talk_run.status
    assert force_talk_run.force_talk?

    # Delete the message
    delete conversation_message_url(conversation, message)

    # Verify the force_talk run was NOT canceled (different kind)
    force_talk_run.reload
    assert_equal "queued", force_talk_run.status
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # during_generation_user_input_policy tests
  # ─────────────────────────────────────────────────────────────────────────────

  test "create with reject policy returns locked when a run is running" do
    # Create a space with reject policy
    space = Spaces::Playground.create!(
      name: "Reject Policy Space",
      owner: users(:admin),
      during_generation_user_input_policy: "reject"
    )
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Test", kind: "root")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    # Create a running run
    running_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: conversation,
      speaker_space_membership: ai_membership,
      status: "running",
      reason: "user_message"
    )

    # Try to create a message - should be blocked (turbo_stream format returns 423)
    assert_no_difference "Message.count" do
      post conversation_messages_url(conversation),
           params: { message: { content: "Blocked message" } },
           as: :turbo_stream
    end

    assert_response :locked

    running_run.destroy!
  end

  test "create with reject policy returns locked when a run is queued" do
    # Create a space with reject policy
    space = Spaces::Playground.create!(
      name: "Reject Policy Space",
      owner: users(:admin),
      during_generation_user_input_policy: "reject"
    )
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Test", kind: "root")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    # Create a queued run
    queued_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: conversation,
      speaker_space_membership: ai_membership,
      status: "queued",
      reason: "user_message"
    )

    # Try to create a message - should be blocked (turbo_stream format returns 423)
    assert_no_difference "Message.count" do
      post conversation_messages_url(conversation),
           params: { message: { content: "Blocked message" } },
           as: :turbo_stream
    end

    assert_response :locked

    queued_run.destroy!
  end

  test "create with queue policy allows message during running run" do
    # The default fixture uses queue policy
    space = @conversation.space
    assert_equal "queue", space.during_generation_user_input_policy

    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    # Create a running run
    running_run = ConversationRun.create!(
      kind: "auto_response",
      conversation: @conversation,
      speaker_space_membership: ai_membership,
      status: "running",
      reason: "user_message"
    )

    # Message creation should still work with queue policy
    assert_difference "Message.count", 1 do
      post conversation_messages_url(@conversation), params: { message: { content: "Allowed message" } }
    end

    assert_redirected_to conversation_url(@conversation, anchor: "message_#{Message.last.id}")

    running_run.destroy!
  end

  test "create with reject policy allows message when no pending runs" do
    # Create a space with reject policy
    space = Spaces::Playground.create!(
      name: "Reject Policy Space",
      owner: users(:admin),
      during_generation_user_input_policy: "reject"
    )
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Test", kind: "root")

    # No pending runs - message creation should work
    assert_difference "Message.count", 1 do
      post conversation_messages_url(conversation), params: { message: { content: "Allowed message" } }
    end

    assert_redirected_to conversation_url(conversation, anchor: "message_#{Message.last.id}")
  end
end
