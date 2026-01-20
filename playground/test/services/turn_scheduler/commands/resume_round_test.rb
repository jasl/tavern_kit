# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Commands
    class ResumeRoundTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space =
          Spaces::Playground.create!(
            name: "ResumeRound Test Space",
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

      test "resumes paused round and schedules current speaker without auto_without_human_delay" do
        @conversation.start_auto_without_human!(rounds: 2)

        travel_to Time.current.change(usec: 0) do
          StartRound.call(conversation: @conversation, is_user_input: false)
          round = @conversation.conversation_rounds.find_by(status: "active")
          assert_not_nil round

          run1 = @conversation.conversation_runs.queued.first
          assert_not_nil run1

          expected_delay = @space.auto_without_human_delay_ms / 1000.0
          assert_in_delta Time.current + expected_delay, run1.run_after, 0.1

          PauseRound.call(conversation: @conversation, reason: "pause_for_resume_test")
          assert_equal "paused", round.reload.scheduling_state
          assert_equal "canceled", run1.reload.status

          resumed = ResumeRound.call(conversation: @conversation, reason: "resume_test")
          assert resumed

          round.reload
          assert_equal "ai_generating", round.scheduling_state

          run2 = @conversation.conversation_runs.queued.first
          assert_not_nil run2
          assert_equal @ai1.id, run2.speaker_space_membership_id
          assert_in_delta Time.current, run2.run_after, 0.1
        end
      end

      test "resumes and skips unschedulable current speaker" do
        @conversation.start_auto_without_human!(rounds: 2)

        StartRound.call(conversation: @conversation, is_user_input: false)
        round = @conversation.conversation_rounds.find_by(status: "active")
        assert_not_nil round

        PauseRound.call(conversation: @conversation, reason: "pause_for_skip_test")
        assert_equal "paused", round.reload.scheduling_state

        # Make the current speaker unschedulable while paused.
        @ai1.update!(participation: "muted")

        resumed = ResumeRound.call(conversation: @conversation, reason: "resume_test")
        assert resumed

        round.reload
        assert_equal "ai_generating", round.scheduling_state
        assert_equal 1, round.current_position

        p1 = round.participants.order(:position).first
        assert_equal "skipped", p1.status

        run = @conversation.conversation_runs.queued.first
        assert_not_nil run
        assert_equal @ai2.id, run.speaker_space_membership_id
      end

      test "does not resume when another run is active" do
        @conversation.start_auto_without_human!(rounds: 2)

        StartRound.call(conversation: @conversation, is_user_input: false)
        round = @conversation.conversation_rounds.find_by(status: "active")
        assert_not_nil round

        PauseRound.call(conversation: @conversation, reason: "pause_for_block_test")
        assert_equal "paused", round.reload.scheduling_state
        assert_empty @conversation.conversation_runs.queued

        other =
          ConversationRun.create!(
            conversation: @conversation,
            kind: "force_talk",
            status: "queued",
            reason: "force_talk",
            speaker_space_membership_id: @ai2.id,
            run_after: Time.current,
            debug: { "trigger" => "force_talk" }
          )

        resumed = ResumeRound.call(conversation: @conversation, reason: "resume_test")
        assert_not resumed

        assert_equal "paused", round.reload.scheduling_state
        assert_equal [other.id], @conversation.conversation_runs.queued.pluck(:id)
      end
    end
  end
end
