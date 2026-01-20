# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Commands
    class PauseRoundTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space =
          Spaces::Playground.create!(
            name: "PauseRound Test Space",
            owner: @user,
            reply_order: "list",
            auto_without_human_delay_ms: 2000
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

      test "pauses active round and cancels queued run" do
        @conversation.start_auto_without_human!(rounds: 2)

        travel_to Time.current.change(usec: 0) do
          StartRound.call(conversation: @conversation, is_user_input: false)

          round = @conversation.conversation_rounds.find_by(status: "active")
          assert_not_nil round
          assert_equal "ai_generating", round.scheduling_state

          run = @conversation.conversation_runs.queued.first
          assert_not_nil run
          assert_equal @ai1.id, run.speaker_space_membership_id

          expected_delay = @space.auto_without_human_delay_ms / 1000.0
          assert_in_delta Time.current + expected_delay, run.run_after, 0.1

          paused = PauseRound.call(conversation: @conversation, reason: "test_pause")
          assert paused

          assert_equal "paused", round.reload.scheduling_state
          assert_equal "canceled", run.reload.status
          assert_empty @conversation.conversation_runs.queued
        end
      end

      test "does not pause a failed round" do
        StartRound.call(conversation: @conversation, is_user_input: false)

        round = @conversation.conversation_rounds.find_by(status: "active")
        assert_not_nil round
        round.update!(scheduling_state: "failed")

        run = @conversation.conversation_runs.queued.first
        assert_not_nil run

        paused = PauseRound.call(conversation: @conversation, reason: "test_pause")
        assert_not paused

        assert_equal "failed", round.reload.scheduling_state
        assert_equal "queued", run.reload.status
      end
    end
  end
end
