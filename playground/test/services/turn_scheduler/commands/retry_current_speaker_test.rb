# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Commands
    class RetryCurrentSpeakerTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space =
          Spaces::Playground.create!(
            name: "RetryCurrentSpeaker Test Space",
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

        ConversationRun.where(conversation: @conversation).delete_all
        TurnScheduler::Broadcasts.stubs(:queue_updated)
      end

      test "re-schedules the current speaker when in failed state" do
        StartRound.call(conversation: @conversation, is_user_input: true)
        @conversation.reload

        state = TurnScheduler.state(@conversation)
        assert_equal @ai1.id, state.current_speaker_id
        assert_equal "ai_generating", state.scheduling_state

        queued = @conversation.conversation_runs.queued.first
        assert_not_nil queued

        active_round = @conversation.conversation_rounds.find_by(status: "active")
        assert_not_nil active_round
        active_round.update!(scheduling_state: "failed")

        ConversationRunJob.stubs(:perform_later)

        run =
          RetryCurrentSpeaker.call(
            conversation: @conversation,
            speaker_id: @ai1.id,
            expected_round_id: active_round.id,
            reason: "test_retry"
          )

        assert_not_nil run
        assert run.queued?
        assert_equal @ai1.id, run.speaker_space_membership_id
        assert_equal "turn_scheduler", run.debug["scheduled_by"]
        assert_equal active_round.id, run.conversation_round_id

        @conversation.reload
        state = TurnScheduler.state(@conversation)
        assert_equal "ai_generating", state.scheduling_state
        assert_equal @ai1.id, state.current_speaker_id
      end

      test "returns nil when not in failed state" do
        StartRound.call(conversation: @conversation, is_user_input: true)
        @conversation.reload
        active_round = @conversation.conversation_rounds.find_by(status: "active")
        assert_not_nil active_round

        ConversationRunJob.stubs(:perform_later)

        run =
          RetryCurrentSpeaker.call(
            conversation: @conversation,
            speaker_id: @ai1.id,
            expected_round_id: active_round.id
          )

        assert_nil run
      end
    end
  end
end
