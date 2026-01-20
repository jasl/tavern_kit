# frozen_string_literal: true

require "test_helper"

class Conversations::RunExecutor::RunClaimerTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    # Avoid TurnScheduler side effects when creating messages in these tests.
    Message.any_instance.stubs(:notify_scheduler_turn_complete)

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
    round = ConversationRound.create!(conversation: @conversation, status: "active", scheduling_state: "ai_generating", current_position: 0)
    round.participants.create!(space_membership: @ai1, position: 0, status: "pending")
    round.participants.create!(space_membership: @ai2, position: 1, status: "pending")

    run =
      ConversationRun.create!(
        kind: "auto_response",
        conversation: @conversation,
        conversation_round_id: round.id,
        status: "queued",
        reason: "auto_response",
        speaker_space_membership_id: @ai1.id,
        run_after: Time.current,
        debug: {
          trigger: "auto_response",
          scheduled_by: "turn_scheduler",
          round_id: round.id,
        }
      )

    # Simulate an environment-driven change that bypasses after_commit callbacks.
    @ai1.update_column(:participation, "muted")

    claimed = Conversations::RunExecutor::RunClaimer.new(run_id: run.id).claim!

    assert_nil claimed

    run.reload
    assert_equal "skipped", run.status
    assert_equal "speaker_unavailable", run.error["code"]

    state = TurnScheduler.state(@conversation.reload)
    assert_equal @ai2.id, state.current_speaker_id
    assert_equal 1, state.round_position

    run2 = @conversation.conversation_runs.queued.first
    assert_not_nil run2
    assert_equal @ai2.id, run2.speaker_space_membership_id
    assert_equal round.id, run2.conversation_round_id
  end

  test "turn_scheduler run kicked after a previous run finishes refreshes expected_last_message_id (queue policy safety)" do
    human = @space.space_memberships.find_by!(kind: "human", user: @user)

    # Seed an initial scheduler-visible tail.
    initial_tail = @conversation.messages.create!(space_membership: human, role: "user", content: "First")

    round = ConversationRound.create!(conversation: @conversation, status: "active", scheduling_state: "ai_generating", current_position: 0)
    round.participants.create!(space_membership: @ai1, position: 0, status: "pending")

    run =
      ConversationRun.create!(
        kind: "auto_response",
        conversation: @conversation,
        conversation_round_id: round.id,
        status: "queued",
        reason: "auto_response",
        speaker_space_membership_id: @ai1.id,
        run_after: Time.current,
        debug: {
          trigger: "auto_response",
          scheduled_by: "turn_scheduler",
          expected_last_message_id: initial_tail.id,
        }
      )

    # Simulate the late completion of the previous run: it creates a new tail message.
    late_tail =
      @conversation.messages.create!(
        space_membership: @ai2,
        role: "assistant",
        content: "Late reply",
        generation_status: "succeeded"
      )

    assert_equal late_tail.id,
                 Message.where(conversation_id: @conversation.id).scheduler_visible.order(seq: :desc, id: :desc).limit(1).pick(:id)

    # Kicking should refresh expected_last_message_id to the current tail, so RunClaimer won't skip it.
    ConversationRunJob.stubs(:perform_later)
    ConversationRunJob.stubs(:set).returns(ConversationRunJob)

    Conversations::RunPlanner.kick!(run, force: true)

    run.reload
    assert_equal late_tail.id, run.debug["expected_last_message_id"]

    claimed = Conversations::RunExecutor::RunClaimer.new(run_id: run.id).claim!
    assert claimed
    assert_equal "running", claimed.status
  end
end
