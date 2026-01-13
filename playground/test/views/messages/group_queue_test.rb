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
end
