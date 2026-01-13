# frozen_string_literal: true

require "test_helper"

module Conversations
  module Messages
    class SwipesControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in :admin

        @space = Spaces::Playground.create!(name: "Swipe Test", owner: users(:admin))
        @space.space_memberships.grant_to(users(:admin), role: "owner")
        @space.space_memberships.grant_to(characters(:ready_v2))

        @conversation = @space.conversations.create!(title: "Main", kind: "root")
        @user_membership = @space.space_memberships.find_by!(user: users(:admin), kind: "human")
        @ai_membership = @space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
      end

      test "swipe on last message succeeds" do
        @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hi")
        last_message = @conversation.messages.create!(space_membership: @ai_membership, role: "assistant", content: "Hello")

        # Add swipes to the message
        last_message.ensure_initial_swipe!
        last_message.add_swipe!(content: "Hello v2")

        # Swipe right should work
        post conversation_message_swipe_url(@conversation, last_message, dir: :right)
        assert_response :no_content
      end

      test "swipe on last message returns turbo_stream replace for turbo_stream request" do
        @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hi")
        last_message = @conversation.messages.create!(space_membership: @ai_membership, role: "assistant", content: "Hello")

        last_message.ensure_initial_swipe!
        last_message.add_swipe!(content: "Hello v2")
        last_message.select_swipe_at!(0)

        post conversation_message_swipe_url(@conversation, last_message, dir: :right), as: :turbo_stream

        assert_turbo_stream(action: "replace", target: ActionView::RecordIdentifier.dom_id(last_message))
        assert_equal "Hello v2", last_message.reload.content
      end

      test "swipe on non-last message is blocked" do
        @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hi")
        first_assistant = @conversation.messages.create!(space_membership: @ai_membership, role: "assistant", content: "Hello")
        @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Thanks")
        @conversation.messages.create!(space_membership: @ai_membership, role: "assistant", content: "You're welcome")

        # Add swipes to the first assistant message
        first_assistant.ensure_initial_swipe!
        first_assistant.add_swipe!(content: "Hello v2")

        # Swiping the first assistant message (not the last message) should fail
        post conversation_message_swipe_url(@conversation, first_assistant, dir: :right)
        assert_response :unprocessable_entity
        assert_equal "Cannot swipe non-last message. Use 'Branch from here' first.", flash[:alert]
      end

      test "swipe on non-last message returns toast turbo_stream without flash" do
        @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hi")
        first_assistant = @conversation.messages.create!(space_membership: @ai_membership, role: "assistant", content: "Hello")
        @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Thanks")
        @conversation.messages.create!(space_membership: @ai_membership, role: "assistant", content: "You're welcome")

        first_assistant.ensure_initial_swipe!
        first_assistant.add_swipe!(content: "Hello v2")

        post conversation_message_swipe_url(@conversation, first_assistant, dir: :right), as: :turbo_stream

        assert_response :unprocessable_entity
        assert_nil flash[:alert]
        assert_match %r{<turbo-stream action="show_toast"}, response.body
        assert_match(/Cannot swipe non-last message/i, response.body)
      end

      test "swipe on non-assistant message is blocked" do
        user_message = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hi")

        post conversation_message_swipe_url(@conversation, user_message, dir: :right)
        assert_response :unprocessable_entity
      end

      test "swipe with invalid direction is blocked" do
        @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hi")
        last_message = @conversation.messages.create!(space_membership: @ai_membership, role: "assistant", content: "Hello")

        post conversation_message_swipe_url(@conversation, last_message, dir: :invalid)
        assert_response :unprocessable_entity
      end
    end
  end
end
