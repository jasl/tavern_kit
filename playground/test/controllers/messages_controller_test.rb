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
end
