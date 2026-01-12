# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  class BroadcastsTest < ActiveSupport::TestCase
    setup do
      @user = users(:admin)
    end

    test "queue_updated increments revision and includes it in payload for non-group conversations" do
      space = Spaces::Playground.create!(name: "Broadcasts Non-Group Space", owner: @user, reply_order: "list")
      conversation = space.conversations.create!(title: "Main")

      space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
      space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

      # Membership after_commit callbacks may have already broadcast queue updates.
      # Reset to a known value to keep the monotonic increment assertion deterministic.
      conversation.update_column(:group_queue_revision, 0)

      ConversationChannel.expects(:broadcast_to).with(
        conversation,
        has_entries(type: "conversation_queue_updated", group_queue_revision: 1)
      )

      Broadcasts.queue_updated(conversation)

      conversation.reload
      assert_equal 1, conversation.group_queue_revision
    end

    test "queue_updated increments revision and includes it in payload for group conversations" do
      space = Spaces::Playground.create!(name: "Broadcasts Group Space", owner: @user, reply_order: "list")
      conversation = space.conversations.create!(title: "Main")

      space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
      space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
      space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

      # Membership after_commit callbacks may have already broadcast queue updates.
      # Reset to a known value to keep the monotonic increment assertion deterministic.
      conversation.update_column(:group_queue_revision, 0)

      ConversationChannel.expects(:broadcast_to).with(
        conversation,
        has_entries(type: "conversation_queue_updated", group_queue_revision: 1)
      )

      Turbo::StreamsChannel.stubs(:broadcast_replace_to)
      Broadcasts.queue_updated(conversation)

      conversation.reload
      assert_equal 1, conversation.group_queue_revision
    end
  end
end
