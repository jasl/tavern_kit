# frozen_string_literal: true

require "test_helper"

class Conversations::RunPlannerTest < ActiveSupport::TestCase
  test "debounce applies delay based on space settings" do
    space =
      Spaces::Playground.create!(
        name: "Debounce Space",
        owner: users(:admin),
        reply_order: "natural",
        user_turn_debounce_ms: 2000
      )

    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    # Clear any auto-created runs from scheduler callbacks
    ConversationRun.where(conversation: conversation).destroy_all

    travel_to Time.current.change(usec: 0) do
      msg1 = conversation.messages.create!(space_membership: user_membership, role: "user", content: "one")

      # Clear any runs created by scheduler to test plan_from_user_message! in isolation
      ConversationRun.where(conversation: conversation).destroy_all

      run1 = Conversations::RunPlanner.plan_from_user_message!(conversation: conversation, user_message: msg1)

      assert_equal "queued", run1.status
      assert_equal msg1.id, run1.debug["user_message_id"]
      # Debounce delay should be applied
      assert_in_delta(Time.current + 2.seconds, run1.run_after, 0.01)
    end
  end

  test "upsert_queued_run updates existing run instead of creating new one" do
    space =
      Spaces::Playground.create!(
        name: "Upsert Space",
        owner: users(:admin),
        reply_order: "natural"
      )

    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    # Clear any auto-created runs
    ConversationRun.where(conversation: conversation).destroy_all

    # Create initial queued run
    run1 = ConversationRun::AutoTurn.create!(
      conversation: conversation,
      status: "queued",
      reason: "test",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current
    )

    # Call upsert_queued_run! - should update existing, not create new
    run2 = Conversations::RunPlanner.send(
      :upsert_queued_run!,
      conversation: conversation,
      reason: "updated_reason",
      speaker_space_membership_id: speaker.id,
      run_after: Time.current + 1.second,
      debug: { updated: true }
    )

    assert_equal run1.id, run2.id
    assert_equal "updated_reason", run2.reason
    assert_equal true, run2.debug["updated"]
    assert_equal 1, conversation.conversation_runs.where(status: "queued").count
  end

  test "manual reply_order does not auto-plan a run from user messages" do
    space = Spaces::Playground.create!(name: "Manual Space", owner: users(:admin), reply_order: "manual")
    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    msg = conversation.messages.create!(space_membership: user_membership, role: "user", content: "hi")
    assert_nil Conversations::RunPlanner.plan_from_user_message!(conversation: conversation, user_message: msg)
    assert_nil conversation.reload.queued_run
  end

  test "force_talk plans a run even when reply_order is manual" do
    space = Spaces::Playground.create!(name: "Manual Force Talk Space", owner: users(:admin), reply_order: "manual")
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run = Conversations::RunPlanner.plan_force_talk!(conversation: conversation, speaker_space_membership_id: speaker.id)

    assert_not_nil run
    assert_equal "queued", run.status
    assert run.is_a?(ConversationRun::ForceTalk)
    assert_equal speaker.id, run.speaker_space_membership_id
  end
end
