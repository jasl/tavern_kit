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

  test "force_talk stops any active scheduling round before queuing a run (strong isolation)" do
    space =
      Spaces::Playground.create!(
        name: "Force Talk Isolation Space",
        owner: users(:admin),
        reply_order: "list"
      )

    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    ai1 = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    ai2 = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    ConversationRun.where(conversation: conversation).delete_all

    TurnScheduler::Commands::StartRound.execute(conversation: conversation, is_user_input: true)
    assert_not TurnScheduler.state(conversation.reload).idle?

    scheduled = ConversationRun.queued.find_by!(conversation_id: conversation.id)
    assert_equal "turn_scheduler", scheduled.debug["scheduled_by"]

    run = Conversations::RunPlanner.plan_force_talk!(conversation: conversation, speaker_space_membership_id: ai2.id)
    assert run
    assert run.force_talk?

    assert TurnScheduler.state(conversation.reload).idle?

    scheduled.reload
    assert_equal "canceled", scheduled.status

    queued = ConversationRun.queued.find_by!(conversation_id: conversation.id)
    assert_equal "force_talk", queued.kind
    assert_equal ai2.id, queued.speaker_space_membership_id
  end

  test "regenerate stops any active scheduling round before queuing a run (strong isolation)" do
    space =
      Spaces::Playground.create!(
        name: "Regenerate Isolation Space",
        owner: users(:admin),
        reply_order: "list"
      )

    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    ai1 = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    ConversationRun.where(conversation: conversation).delete_all

    # Create a target assistant message to regenerate.
    target = conversation.messages.create!(
      space_membership: ai1,
      role: "assistant",
      content: "Original response",
      generation_status: "succeeded"
    )

    TurnScheduler::Commands::StartRound.execute(conversation: conversation, is_user_input: true)
    assert_not TurnScheduler.state(conversation.reload).idle?

    scheduled = ConversationRun.queued.find_by!(conversation_id: conversation.id)
    assert_equal "turn_scheduler", scheduled.debug["scheduled_by"]

    run = Conversations::RunPlanner.plan_regenerate!(conversation: conversation, target_message: target)
    assert run
    assert run.regenerate?

    assert TurnScheduler.state(conversation.reload).idle?

    scheduled.reload
    assert_equal "canceled", scheduled.status

    queued = ConversationRun.queued.find_by!(conversation_id: conversation.id)
    assert_equal "regenerate", queued.kind
    assert_equal ai1.id, queued.speaker_space_membership_id
  end
end
