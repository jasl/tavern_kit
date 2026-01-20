# frozen_string_literal: true

require "test_helper"

module Conversations
  module Messages
    class VisibilitiesControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in :admin

        @space = Spaces::Playground.create!(name: "Visibility Test", owner: users(:admin))
        @space.space_memberships.grant_to(users(:admin), role: "owner")
        @space.space_memberships.grant_to(characters(:ready_v2))

        @conversation = @space.conversations.create!(title: "Main", kind: "root")
        @user_membership = @space.space_memberships.find_by!(user: users(:admin), kind: "human")
        @ai_membership = @space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
      end

      test "toggle excludes message from prompt" do
        message = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello"
        )

        assert message.visibility_normal?

        patch conversation_message_visibility_url(@conversation, message),
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        assert_response :success

        message.reload
        assert message.visibility_excluded?
      end

      test "toggle includes previously excluded message in prompt" do
        message = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello",
          visibility: "excluded"
        )

        assert message.visibility_excluded?

        patch conversation_message_visibility_url(@conversation, message),
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        assert_response :success

        message.reload
        assert message.visibility_normal?
      end

      test "toggle works for assistant messages" do
        @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hi"
        )

        message = @conversation.messages.create!(
          space_membership: @ai_membership,
          role: "assistant",
          content: "Hello back!"
        )

        assert message.visibility_normal?

        patch conversation_message_visibility_url(@conversation, message),
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        assert_response :success

        message.reload
        assert message.visibility_excluded?
      end

      test "toggle requires space membership" do
        sign_in :member

        message = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello"
        )

        patch conversation_message_visibility_url(@conversation, message)
        assert_response :not_found
      end

      test "toggle returns turbo stream response" do
        message = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello"
        )

        patch conversation_message_visibility_url(@conversation, message),
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        assert_response :success
        assert_match "turbo-stream", response.body
      end
    end
  end
end
