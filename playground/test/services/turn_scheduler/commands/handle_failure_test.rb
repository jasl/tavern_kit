# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Commands
    class HandleFailureTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space =
          Spaces::Playground.create!(
            name: "HandleFailure Test Space",
            owner: @user,
            reply_order: "list"
          )
        @conversation = @space.conversations.create!(title: "Main")

        @human =
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
      end

      test "marks scheduler failed, cancels queued runs, and preserves round state" do
        @conversation.start_auto_without_human!(rounds: 2)

        persona =
          Character.create!(
            name: "HandleFailure Persona",
            personality: "Test",
            data: { "name" => "HandleFailure Persona" },
            spec_version: 2,
            file_sha256: "handle_failure_persona_#{SecureRandom.hex(8)}",
            status: "ready",
            visibility: "private"
          )

        @human.update!(character: persona, auto: "auto", auto_remaining_steps: 4)
        assert @conversation.auto_without_human_enabled?
        assert @human.auto_enabled?

        round =
          ConversationRound.create!(
            conversation: @conversation,
            status: "active",
            scheduling_state: "ai_generating",
            current_position: 0
          )
        round.participants.create!(space_membership: @ai1, position: 0)
        round.participants.create!(space_membership: @ai2, position: 1)

        failing_run =
          ConversationRun.create!(
            conversation: @conversation,
            speaker_space_membership_id: @ai1.id,
            kind: "auto_response",
            status: "failed",
            reason: "auto_response",
            error: { "code" => "test_error" },
            conversation_round_id: round.id,
            debug: {
              "trigger" => "auto_response",
              "scheduled_by" => "turn_scheduler",
            }
          )

        queued_run =
          ConversationRun.create!(
            conversation: @conversation,
            speaker_space_membership_id: @ai2.id,
            kind: "auto_response",
            status: "queued",
            reason: "auto_response",
            run_after: Time.current,
            conversation_round_id: round.id,
            debug: {
              "trigger" => "auto_response",
              "scheduled_by" => "turn_scheduler",
            }
          )

        TurnScheduler::Broadcasts.expects(:queue_updated).with(@conversation)
        Messages::Broadcasts.expects(:broadcast_auto_disabled).with(@human, reason: "turn_failed")

        handled = HandleFailure.execute(conversation: @conversation, run: failing_run, error: failing_run.error)

        assert handled

        assert_equal "canceled", queued_run.reload.status

        round.reload
        assert_equal "active", round.status
        assert_equal "failed", round.scheduling_state
        assert_equal 0, round.current_position

        state = TurnScheduler.state(@conversation.reload)
        assert_equal round.id, state.current_round_id
        assert_equal @ai1.id, state.current_speaker_id
        assert_equal 0, state.round_position
        assert_equal [@ai1.id, @ai2.id], state.round_queue_ids
        assert_equal [], state.round_spoken_ids

        assert_not @conversation.reload.auto_without_human_enabled?
        assert @human.reload.auto_none?
        assert_nil @human.auto_remaining_steps
      end

      test "returns false when run is not scheduled by turn_scheduler" do
        round =
          ConversationRound.create!(
            conversation: @conversation,
            status: "active",
            scheduling_state: "ai_generating",
            current_position: 0
          )
        round.participants.create!(space_membership: @ai1, position: 0)
        round.participants.create!(space_membership: @ai2, position: 1)

        failing_run =
          ConversationRun.create!(
            conversation: @conversation,
            speaker_space_membership_id: @ai1.id,
            kind: "auto_response",
            status: "failed",
            reason: "auto_response",
            error: { "code" => "test_error" },
            debug: {
              "trigger" => "auto_response",
              "scheduled_by" => "run_planner",
            }
          )

        queued_run =
          ConversationRun.create!(
            conversation: @conversation,
            speaker_space_membership_id: @ai2.id,
            kind: "auto_response",
            status: "queued",
            reason: "auto_response",
            run_after: Time.current,
            debug: { "trigger" => "auto_response" }
          )

        TurnScheduler::Broadcasts.expects(:queue_updated).never

        response = HandleFailure.execute(conversation: @conversation, run: failing_run, error: failing_run.error)

        assert_not response.payload[:handled]
        assert_equal :noop_not_scheduler_run, response.reason
        assert_equal "queued", queued_run.reload.status
        assert_equal "ai_generating", round.reload.scheduling_state
      end

      test "returns false when run round_id does not match current round" do
        stale_round_id = SecureRandom.uuid

        round =
          ConversationRound.create!(
            conversation: @conversation,
            status: "active",
            scheduling_state: "ai_generating",
            current_position: 0
          )
        round.participants.create!(space_membership: @ai1, position: 0)
        round.participants.create!(space_membership: @ai2, position: 1)

        ConversationRound.create!(
          id: stale_round_id,
          conversation: @conversation,
          status: "finished",
          scheduling_state: nil,
          current_position: 0
        )

        failing_run =
          ConversationRun.create!(
            conversation: @conversation,
            speaker_space_membership_id: @ai1.id,
            kind: "auto_response",
            status: "failed",
            reason: "auto_response",
            error: { "code" => "test_error" },
            conversation_round_id: stale_round_id,
            debug: {
              "trigger" => "auto_response",
              "scheduled_by" => "turn_scheduler",
            }
          )

        queued_run =
          ConversationRun.create!(
            conversation: @conversation,
            speaker_space_membership_id: @ai2.id,
            kind: "auto_response",
            status: "queued",
            reason: "auto_response",
            run_after: Time.current,
            debug: { "trigger" => "auto_response" }
          )

        TurnScheduler::Broadcasts.expects(:queue_updated).never

        response = HandleFailure.execute(conversation: @conversation, run: failing_run, error: failing_run.error)

        assert_not response.payload[:handled]
        assert_equal :noop_stale_round, response.reason
        assert_equal "queued", queued_run.reload.status
        assert_equal "ai_generating", round.reload.scheduling_state
      end
    end
  end
end
