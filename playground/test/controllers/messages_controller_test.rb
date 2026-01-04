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
    assert_equal "user_turn", run.kind
    assert_equal space_memberships(:character_in_general).id, run.speaker_space_membership_id
    assert_equal msg.id, run.debug["user_message_id"]

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

  test "index returns forbidden when user is not a member of the space" do
    # Create a new space that the admin user is NOT a member of
    other_user = users(:member)
    other_space = Spaces::Playground.create!(name: "Private Space", owner: other_user)
    other_space.space_memberships.grant_to(other_user, role: "owner")
    other_space.space_memberships.grant_to(characters(:ready_v2))
    other_conversation = other_space.conversations.create!(title: "Private Chat")

    # Admin should not be able to access messages in this space
    get conversation_messages_url(other_conversation)

    assert_response :forbidden
  end

  test "show returns forbidden when user is not a member of the space" do
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

    get conversation_message_url(other_conversation, other_message)

    assert_response :forbidden
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

  test "destroy on non-tail message returns unprocessable_entity" do
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

    # Try to delete the first (non-tail) message
    assert_no_difference "Message.count" do
      delete conversation_message_url(@conversation, first_message)
    end

    assert_redirected_to conversation_url(@conversation)
    assert_match(/cannot.*(edit|delete)/i, flash[:alert])
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

    assert_difference "Message.count", -1 do
      delete conversation_message_url(@conversation, last_message)
    end
  end

  test "destroy cancels queued run triggered by the deleted message" do
    user_membership = space_memberships(:admin_in_general)

    # Create a message and trigger a queued run
    message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Message to delete"
    )

    # Plan a run triggered by this message
    queued_run = Conversation::RunPlanner.plan_from_user_message!(
      conversation: @conversation,
      user_message: message
    )

    assert queued_run, "Expected a queued run to be created"
    assert_equal "queued", queued_run.status
    assert_equal "user_turn", queued_run.kind
    assert_equal "user_message", queued_run.debug["trigger"]
    assert_equal message.id, queued_run.debug["user_message_id"]

    # Delete the message
    assert_difference "Message.count", -1 do
      delete conversation_message_url(@conversation, message)
    end

    # Verify the queued run was canceled
    queued_run.reload
    assert_equal "canceled", queued_run.status
    assert_not_nil queued_run.finished_at
  end

  test "destroy cancels queued run even when multiple messages were created" do
    user_membership = space_memberships(:admin_in_general)

    # Create first message and plan a run
    first_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "First message"
    )

    queued_run = Conversation::RunPlanner.plan_from_user_message!(
      conversation: @conversation,
      user_message: first_message
    )

    # Create second message (this becomes the tail)
    # The RunPlanner upserts the queued run to point to the new message
    second_message = @conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Second message"
    )

    # Simulate the upsert behavior - in real usage, plan_from_user_message! would be called
    # but here we manually verify the run was updated
    Conversation::RunPlanner.plan_from_user_message!(
      conversation: @conversation,
      user_message: second_message
    )

    queued_run.reload
    assert_equal second_message.id, queued_run.debug["user_message_id"]

    # Delete the second message (tail)
    assert_difference "Message.count", -1 do
      delete conversation_message_url(@conversation, second_message)
    end

    # Verify the queued run was canceled (it was triggered by second_message)
    queued_run.reload
    assert_equal "canceled", queued_run.status
    assert_not_nil queued_run.finished_at
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
    force_talk_run = Conversation::RunPlanner.plan_force_talk!(
      conversation: conversation,
      speaker_space_membership_id: ai_membership.id
    )

    assert force_talk_run, "Expected a queued run to be created"
    assert_equal "queued", force_talk_run.status
    assert_equal "force_talk", force_talk_run.kind

    # Delete the message
    delete conversation_message_url(conversation, message)

    # Verify the force_talk run was NOT canceled (different kind)
    force_talk_run.reload
    assert_equal "queued", force_talk_run.status
  end
end
