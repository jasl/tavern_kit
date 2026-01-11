# frozen_string_literal: true

require "test_helper"

class SpaceDeleteJobTest < ActiveSupport::TestCase
  test "deletes space and associated conversations/messages/memberships/runs" do
    space = Spaces::Playground.create!(name: "Delete Me", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.grant_to([users(:admin), characters(:ready_v2)])

    user_membership = space.space_memberships.find_by!(user: users(:admin))
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2))

    3.times { |i| conversation.messages.create!(space_membership: user_membership, role: "user", content: "m#{i}") }

    membership_count = SpaceMembership.where(space_id: space.id).count

    trigger = conversation.messages.create!(space_membership: user_membership, role: "user", content: "trigger")
    running =
      ConversationRun.create!(kind: "auto_response", conversation: conversation,

        status: "running",
        reason: "test",
        speaker_space_membership_id: ai_membership.id,
        started_at: Time.current,
        heartbeat_at: Time.current
      )

    assistant =
      conversation.messages.create!(
        space_membership: ai_membership,
        role: "assistant",
        content: "hi",
        conversation_run: running
      )

    # Clear any auto-created runs from membership callbacks before creating test runs
    ConversationRun.where(conversation: conversation).where.not(id: running.id).destroy_all

    ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "queued",
      reason: "test",
      speaker_space_membership_id: ai_membership.id,
      run_after: 1.minute.from_now,
      debug: { expected_last_message_id: assistant.id }
    )

    message_count = Message.where(conversation_id: conversation.id).count
    conversation_run_count = ConversationRun.where(conversation_id: conversation.id).count

    assert_difference "Space.count", -1 do
      assert_difference "Conversation.count", -1 do
        assert_difference "Message.count", -message_count do
          assert_difference "SpaceMembership.count", -membership_count do
            assert_difference "ConversationRun.count", -conversation_run_count do
              SpaceDeleteJob.perform_now(space.id)
            end
          end
        end
      end
    end
  end

  test "re-enqueues when messages remain after batch limit" do
    space = Spaces::Playground.create!(name: "Delete Me", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    space.space_memberships.grant_to([users(:admin), characters(:ready_v2)])

    user_membership = space.space_memberships.find_by!(user: users(:admin))
    3.times { |i| conversation.messages.create!(space_membership: user_membership, role: "user", content: "m#{i}") }

    assert_enqueued_with(job: SpaceDeleteJob, args: [space.id, { batch_size: 1, max_batches: 1 }]) do
      SpaceDeleteJob.perform_now(space.id, batch_size: 1, max_batches: 1)
    end

    assert Space.exists?(space.id)
    assert_equal "deleting", space.reload.status
    assert Message.exists?(conversation_id: conversation.id)
  end

  test "discards when space not found" do
    assert_nothing_raised do
      SpaceDeleteJob.perform_now(999_999)
    end
  end
end
