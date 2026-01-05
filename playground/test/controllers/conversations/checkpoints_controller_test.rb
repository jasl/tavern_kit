# frozen_string_literal: true

require "test_helper"

module Conversations
  class CheckpointsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in users(:admin)
      @space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
      @space.space_memberships.grant_to(users(:admin), role: "owner")
      @space.space_memberships.grant_to(characters(:ready_v2))

      @conversation = @space.conversations.create!(title: "Main", kind: "root")
      @user_membership = @space.space_memberships.find_by!(user: users(:admin), kind: "human")
      @ai_membership = @space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    end

    test "checkpoint creates a new conversation with kind checkpoint" do
      msg = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "First message"
      )

      assert_difference "Conversation.count", 1 do
        post conversation_checkpoints_url(@conversation), params: { message_id: msg.id }
      end

      checkpoint = Conversation.order(:created_at, :id).last
      assert_equal "checkpoint", checkpoint.kind
    end

    test "checkpoint does not redirect to new conversation" do
      msg = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "Test message"
      )

      post conversation_checkpoints_url(@conversation),
           params: { message_id: msg.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      # Should NOT redirect to the new checkpoint (unlike branch)
      # For turbo stream requests, returns success with toast
      assert_response :success
    end

    test "checkpoint copies messages up to the specified message" do
      m1 = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "First"
      )
      m2 = @conversation.messages.create!(
        space_membership: @ai_membership,
        role: "assistant",
        content: "Second"
      )
      _m3 = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "Third"
      )

      post conversation_checkpoints_url(@conversation), params: { message_id: m2.id }

      checkpoint = Conversation.order(:created_at, :id).last
      assert_equal 2, checkpoint.messages.count
      contents = checkpoint.messages.order(:seq).pluck(:content)
      assert_equal ["First", "Second"], contents
    end

    test "checkpoint inherits authors_note from parent" do
      @conversation.update!(authors_note: "INHERITED_NOTE")

      msg = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "Test"
      )

      post conversation_checkpoints_url(@conversation), params: { message_id: msg.id }

      checkpoint = Conversation.order(:created_at, :id).last
      assert_equal "INHERITED_NOTE", checkpoint.authors_note
    end

    test "checkpoint preserves excluded_from_prompt flag on messages" do
      m1 = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "Included message"
      )
      m2 = @conversation.messages.create!(
        space_membership: @ai_membership,
        role: "assistant",
        content: "Excluded message",
        excluded_from_prompt: true
      )

      post conversation_checkpoints_url(@conversation), params: { message_id: m2.id }

      checkpoint = Conversation.order(:created_at, :id).last
      cloned_m1, cloned_m2 = checkpoint.messages.order(:seq).to_a

      assert_not cloned_m1.excluded_from_prompt?
      assert cloned_m2.excluded_from_prompt?
    end

    test "checkpoint uses custom title when provided" do
      msg = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "Test"
      )

      post conversation_checkpoints_url(@conversation),
           params: { message_id: msg.id, title: "My Custom Checkpoint" }

      checkpoint = Conversation.order(:created_at, :id).last
      assert_equal "My Custom Checkpoint", checkpoint.title
    end

    test "checkpoint generates default title with message seq" do
      msg = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "Test"
      )

      post conversation_checkpoints_url(@conversation), params: { message_id: msg.id }

      checkpoint = Conversation.order(:created_at, :id).last
      assert_match(/Checkpoint at message ##{msg.seq}/, checkpoint.title)
    end

    test "checkpoint returns not_found for invalid message_id" do
      post conversation_checkpoints_url(@conversation),
           params: { message_id: 999999 },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :not_found
    end

    test "checkpoint redirects with alert for invalid message_id in HTML format" do
      post conversation_checkpoints_url(@conversation), params: { message_id: 999999 }

      assert_redirected_to conversation_url(@conversation)
      assert_equal "Message not found", flash[:alert]
    end

    test "checkpoint sets correct parent and root relationships" do
      msg = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "Test"
      )

      post conversation_checkpoints_url(@conversation), params: { message_id: msg.id }

      checkpoint = Conversation.order(:created_at, :id).last
      assert_equal @conversation, checkpoint.parent_conversation
      assert_equal @conversation.root_conversation, checkpoint.root_conversation
      assert_equal msg, checkpoint.forked_from_message
    end

    test "checkpoint returns turbo_stream response" do
      msg = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "Test"
      )

      post conversation_checkpoints_url(@conversation),
           params: { message_id: msg.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_match(/turbo-stream/, response.content_type)
    end

    test "checkpoint requires space membership" do
      sign_out
      sign_in users(:member)

      msg = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "Test"
      )

      assert_no_difference "Conversation.count" do
        post conversation_checkpoints_url(@conversation), params: { message_id: msg.id }
      end

      # Non-members get 404 (conversation not visible to them)
      assert_response :not_found
    end

    test "checkpoint returns forbidden when space is archived" do
      @space.update!(status: "archived")

      msg = @conversation.messages.create!(
        space_membership: @user_membership,
        role: "user",
        content: "Test"
      )

      assert_no_difference "Conversation.count" do
        post conversation_checkpoints_url(@conversation), params: { message_id: msg.id }
      end

      assert_response :forbidden
    end
  end
end
