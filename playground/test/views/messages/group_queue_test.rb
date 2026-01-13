# frozen_string_literal: true

require "test_helper"

class Messages::GroupQueueTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
  end

  test "renders 'Your turn' when scheduler is idle even if a run is still active" do
    space = Spaces::Playground.create!(name: "GroupQueue View Space", owner: @user, reply_order: "list")
    conversation = space.conversations.create!(title: "Main")

    human = space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    ai = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    # No active round => scheduler idle
    assert_nil conversation.conversation_rounds.find_by(status: "active")
    assert_equal "idle", TurnScheduler.state(conversation).scheduling_state

    # Simulate the "message already persisted but run not yet finalized" window:
    # active_run exists, but scheduler is idle.
    ConversationRun.create!(
      conversation: conversation,
      speaker_space_membership: ai,
      status: "running",
      kind: "auto_response",
      reason: "test",
      started_at: Time.current,
      heartbeat_at: Time.current
    )

    presenter = GroupQueuePresenter.new(conversation: conversation, space: space)
    assert presenter.active_run.present?
    assert presenter.idle?

    html = ApplicationController.render(
      partial: "messages/group_queue",
      locals: { presenter: presenter }
    )

    assert_includes html, "Your turn"
    assert_not_includes html, "loading-spinner"
    assert_not_includes html, human.display_name # sanity: not accidentally rendering speaker name
  end

  test "current_speaker uses round's current speaker even if old run is still running" do
    space = Spaces::Playground.create!(name: "GroupQueue Sync Space", owner: @user, reply_order: "list")
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    ai_alice = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    ai_bob = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    # Simulate: Alice's run created message, round advanced to Bob, but Alice's run not yet finalized
    # 1. Create an active round with Bob as current speaker (position 1)
    round = ConversationRound.create!(
      conversation: conversation,
      status: "active",
      scheduling_state: "ai_generating",
      current_position: 1  # Bob is current speaker
    )
    round.participants.create!(space_membership: ai_alice, position: 0, status: "spoken", spoken_at: Time.current)
    round.participants.create!(space_membership: ai_bob, position: 1, status: "pending")

    # 2. Alice's old run is still "running" (not yet finalized)
    old_run = ConversationRun.create!(
      conversation: conversation,
      conversation_round: round,
      speaker_space_membership: ai_alice,
      status: "running",
      kind: "auto_response",
      reason: "test",
      started_at: Time.current,
      heartbeat_at: Time.current
    )

    # 3. Bob's new run is "queued"
    ConversationRun.create!(
      conversation: conversation,
      conversation_round: round,
      speaker_space_membership: ai_bob,
      status: "queued",
      kind: "auto_response",
      reason: "test"
    )

    presenter = GroupQueuePresenter.new(conversation: conversation, space: space)

    # Verify: active_run finds Alice's running run (by status priority)
    assert_equal old_run.id, presenter.active_run.id
    assert_equal "running", presenter.active_run.status

    # But current_speaker should be Bob (from round's current_position), not Alice
    assert_equal ai_bob.id, presenter.current_speaker.id
    assert_equal ai_bob.display_name, presenter.current_speaker.display_name

    # Render and verify Bob is shown as current speaker
    html = ApplicationController.render(
      partial: "messages/group_queue",
      locals: { presenter: presenter }
    )

    assert_includes html, ai_bob.display_name
    assert_includes html, "loading-spinner"
  end
end
