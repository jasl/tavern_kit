# frozen_string_literal: true

require "test_helper"

class Conversations::RunExecutor::RunClaimerTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space =
      Spaces::Playground.create!(
        name: "RunClaimer Test Space",
        owner: @user,
        reply_order: "list"
      )
    @conversation = @space.conversations.create!(title: "Main")

    @space.space_memberships.create!(
      kind: "human",
      role: "owner",
      user: @user,
      position: 0
    )

    @ai1 =
      @space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v2),
        position: 1
      )

    @ai2 =
      @space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v3),
        position: 2
      )

    ConversationRun.where(conversation: @conversation).delete_all
    TurnScheduler::Broadcasts.stubs(:queue_updated)
  end

  test "turn_scheduler run is skipped when speaker becomes unavailable, and scheduler advances" do
    round_id = SecureRandom.uuid

    @conversation.update!(
      scheduling_state: "ai_generating",
      current_round_id: round_id,
      current_speaker_id: @ai1.id,
      round_position: 0,
      round_spoken_ids: [],
      round_queue_ids: [@ai1.id, @ai2.id]
    )

    run =
      ConversationRun.create!(
        kind: "auto_response",
        conversation: @conversation,
        status: "queued",
        reason: "auto_response",
        speaker_space_membership_id: @ai1.id,
        run_after: Time.current,
        debug: {
          trigger: "auto_response",
          scheduled_by: "turn_scheduler",
          round_id: round_id,
        }
      )

    # Simulate an environment-driven change that bypasses after_commit callbacks.
    @ai1.update_column(:participation, "muted")

    claimed = Conversations::RunExecutor::RunClaimer.new(run_id: run.id).claim!

    assert_nil claimed

    run.reload
    assert_equal "skipped", run.status
    assert_equal "speaker_unavailable", run.error["code"]

    @conversation.reload
    assert_equal @ai2.id, @conversation.current_speaker_id
    assert_equal 1, @conversation.round_position

    run2 = @conversation.conversation_runs.queued.first
    assert_not_nil run2
    assert_equal @ai2.id, run2.speaker_space_membership_id
  end
end
