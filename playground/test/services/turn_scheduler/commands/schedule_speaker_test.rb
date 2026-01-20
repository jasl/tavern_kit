# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Commands
    class ScheduleSpeakerTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space = Spaces::Playground.create!(
          name: "ScheduleSpeaker Test Space",
          owner: @user,
          reply_order: "natural",
          auto_without_human_delay_ms: 2000
        )
        @conversation = @space.conversations.create!(title: "Main")
        @user_membership = @space.space_memberships.create!(
          kind: "human",
          role: "owner",
          user: @user,
          position: 0
        )
        @ai_character = @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: characters(:ready_v2),
          position: 1,
          llm_provider: llm_providers(:openai)
        )

        @round = ConversationRound.create!(
          conversation: @conversation,
          status: "active",
          scheduling_state: "ai_generating",
          current_position: 0
        )

        ConversationRun.where(conversation: @conversation).delete_all
      end

      test "creates auto_response run for AI character" do
        run = ScheduleSpeaker.call(conversation: @conversation, speaker: @ai_character, conversation_round: @round)

        assert_not_nil run
        assert_equal "queued", run.status
        assert_equal "auto_response", run.kind
        assert_equal @ai_character.id, run.speaker_space_membership_id
        assert_equal @round.id, run.conversation_round_id
      end

      test "creates auto_user_response run for auto user" do
        @user_membership.update!(
          character: characters(:ready_v3),
          auto: "auto",
          auto_remaining_steps: 3,
          llm_provider: llm_providers(:openai)
        )

        run = ScheduleSpeaker.call(conversation: @conversation, speaker: @user_membership, conversation_round: @round)

        assert_not_nil run
        assert_equal "auto_user_response", run.kind
        assert_equal @round.id, run.conversation_round_id
      end

      test "applies auto_without_human_delay to run_after when auto_without_human active" do
        @conversation.start_auto_without_human!(rounds: 2)

        travel_to Time.current.change(usec: 0) do
          run = ScheduleSpeaker.call(conversation: @conversation, speaker: @ai_character, conversation_round: @round)

          assert_not_nil run.run_after
          expected_delay = @space.auto_without_human_delay_ms / 1000.0
          assert_in_delta Time.current + expected_delay, run.run_after, 0.1
        end
      end

      test "no delay when auto mode is not active" do
        travel_to Time.current.change(usec: 0) do
          run = ScheduleSpeaker.call(conversation: @conversation, speaker: @ai_character, conversation_round: @round)

          # Run should be immediate or very close to now
          assert run.run_after.nil? || run.run_after <= Time.current + 1.second
        end
      end

      test "returns nil for pure human without auto mode" do
        run = ScheduleSpeaker.call(conversation: @conversation, speaker: @user_membership)

        assert_nil run, "Should not create run for pure human without auto mode"
      end

      test "returns nil for pure human even in auto mode" do
        @conversation.start_auto_without_human!(rounds: 2)

        run = ScheduleSpeaker.call(conversation: @conversation, speaker: @user_membership)

        assert_nil run, "Pure humans are not scheduled by TurnScheduler"
      end

      test "returns nil if queued run already exists" do
        # Create existing queued run
        ConversationRun.create!(
          conversation: @conversation,
          status: "queued",
          kind: "auto_response",
          reason: "existing",
          speaker_space_membership_id: @ai_character.id
        )

        run = ScheduleSpeaker.call(conversation: @conversation, speaker: @ai_character, conversation_round: @round)

        assert_nil run, "Should not create duplicate queued run"
      end

      test "enqueues ConversationRunJob for AI turn" do
        assert_enqueued_with(job: ConversationRunJob) do
          ScheduleSpeaker.call(conversation: @conversation, speaker: @ai_character, conversation_round: @round)
        end
      end

      test "schedules job with delay when run_after is future" do
        @conversation.start_auto_without_human!(rounds: 2)

        run = ScheduleSpeaker.call(conversation: @conversation, speaker: @ai_character, conversation_round: @round)

        # Job should be enqueued
        assert run.present?
        assert_enqueued_jobs 1, only: ConversationRunJob
      end

      test "returns nil for nil speaker" do
        run = ScheduleSpeaker.call(conversation: @conversation, speaker: nil)

        assert_nil run
      end

      test "does not kick run if running run exists" do
        ConversationRun.create!(
          conversation: @conversation,
          status: "running",
          kind: "auto_response",
          reason: "blocking_run",
          speaker_space_membership_id: @ai_character.id,
          started_at: Time.current
        )

        assert_no_enqueued_jobs only: ConversationRunJob do
          run = ScheduleSpeaker.call(conversation: @conversation, speaker: @ai_character, conversation_round: @round)
          assert_not_nil run
          assert_equal "queued", run.status
          assert_nil run.debug["last_kicked_at_ms"]
        end
      end

      test "records kick metadata in run debug" do
        run = ScheduleSpeaker.call(conversation: @conversation, speaker: @ai_character, conversation_round: @round)

        assert_not_nil run
        assert run.debug["last_kicked_at_ms"].present?
        assert_equal 1, run.debug["kicked_count"]
      end
    end
  end
end
