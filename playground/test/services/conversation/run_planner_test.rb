# frozen_string_literal: true

require "test_helper"

class Conversation::RunPlannerTest < ActiveSupport::TestCase
  test "debounce upserts queued run and extends run_after" do
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

    travel_to Time.current.change(usec: 0) do
      msg1 = conversation.messages.create!(space_membership: user_membership, role: "user", content: "one")
      run1 = Conversation::RunPlanner.plan_from_user_message!(conversation: conversation, user_message: msg1)

      assert_equal "queued", run1.status
      assert_equal msg1.id, run1.debug["user_message_id"]
      assert_in_delta(Time.current + 2.seconds, run1.run_after, 0.01)

      travel 1.second

      msg2 = conversation.messages.create!(space_membership: user_membership, role: "user", content: "two")
      run2 = Conversation::RunPlanner.plan_from_user_message!(conversation: conversation, user_message: msg2)

      assert_equal run1.id, run2.id
      assert_equal msg2.id, run2.debug["user_message_id"]
      assert run2.run_after > run1.run_after
      assert_equal 1, conversation.conversation_runs.where(status: "queued").count
    end
  end

  test "manual reply_order does not auto-plan a run from user messages" do
    space = Spaces::Playground.create!(name: "Manual Space", owner: users(:admin), reply_order: "manual")
    conversation = space.conversations.create!(title: "Main")

    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    msg = conversation.messages.create!(space_membership: user_membership, role: "user", content: "hi")
    assert_nil Conversation::RunPlanner.plan_from_user_message!(conversation: conversation, user_message: msg)
    assert_nil conversation.reload.queued_run
  end

  test "force_talk plans a run even when reply_order is manual" do
    space = Spaces::Playground.create!(name: "Manual Force Talk Space", owner: users(:admin), reply_order: "manual")
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run = Conversation::RunPlanner.plan_force_talk!(conversation: conversation, speaker_space_membership_id: speaker.id)

    assert_not_nil run
    assert_equal "queued", run.status
    assert_equal "force_talk", run.kind
    assert_equal speaker.id, run.speaker_space_membership_id
  end

  test "auto_mode followup does not override an existing queued run" do
    space =
      Spaces::Playground.create!(
        name: "Auto Mode Space",
        owner: users(:admin),
        reply_order: "natural",
        auto_mode_enabled: true,
        allow_self_responses: true
      )

    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    existing =
      conversation.conversation_runs.create!(
        kind: "user_turn",
        status: "queued",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        run_after: Time.current
      )

    trigger = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "hi")

    assert_nil Conversation::RunPlanner.plan_auto_mode_followup!(conversation: conversation, trigger_message: trigger)
    assert_equal existing.id, conversation.reload.queued_run&.id
  end

  test "auto_mode followup creates queued run with expected_last_message_id in debug and delay" do
    space =
      Spaces::Playground.create!(
        name: "Auto Mode Delay Space",
        owner: users(:admin),
        reply_order: "natural",
        auto_mode_enabled: true,
        auto_mode_delay_ms: 1000,
        allow_self_responses: true
      )

    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    trigger = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "hi")

    travel_to Time.current.change(usec: 0) do
      run = Conversation::RunPlanner.plan_auto_mode_followup!(conversation: conversation, trigger_message: trigger)

      assert_not_nil run
      assert_equal "queued", run.status
      assert_equal "auto_mode", run.kind
      assert_equal trigger.id, run.debug["expected_last_message_id"]
      assert_in_delta(Time.current + 1.second, run.run_after, 0.01)
    end
  end
end
