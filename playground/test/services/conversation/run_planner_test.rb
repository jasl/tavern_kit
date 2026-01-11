# frozen_string_literal: true

require "test_helper"

class Conversations::RunPlannerTest < ActiveSupport::TestCase
  # NOTE: The plan_from_user_message! method was removed as its functionality
  # is now handled by TurnScheduler::Commands::AdvanceTurn via Message#after_create_commit.
  # Debounce testing is now in turn_scheduler_test.rb.

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
    run1 = ConversationRun.create!(kind: "auto_response",
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
      kind: "auto_response",
      debug: { updated: true }
    )

    assert_equal run1.id, run2.id
    assert_equal "updated_reason", run2.reason
    assert_equal true, run2.debug["updated"]
    assert_equal 1, conversation.conversation_runs.where(status: "queued").count
  end

  # NOTE: Manual mode auto-planning is now tested via TurnScheduler tests.

  test "force_talk plans a run even when reply_order is manual" do
    space = Spaces::Playground.create!(name: "Manual Force Talk Space", owner: users(:admin), reply_order: "manual")
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    run = Conversations::RunPlanner.plan_force_talk!(conversation: conversation, speaker_space_membership_id: speaker.id)

    assert_not_nil run
    assert_equal "queued", run.status
    assert run.force_talk?
    assert_equal speaker.id, run.speaker_space_membership_id
  end
end
