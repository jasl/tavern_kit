# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Commands
    class StartRoundTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space = Spaces::Playground.create!(
          name: "StartRound Test Space",
          owner: @user,
          reply_order: "natural"
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
          position: 1
        )

        # Clear any auto-created runs
        ConversationRun.where(conversation: @conversation).delete_all
      end

      test "starts a round and sets scheduling state" do
        # Use deterministic RNG for predictable tests
        rng = Random.new(42)

        result = StartRound.call(
          conversation: @conversation,
          is_user_input: true,
          rng: rng
        )

        assert result, "Should return true on success"

        @conversation.reload
        assert_not_nil @conversation.current_round_id, "Should set round_id"
        assert_not_nil @conversation.current_speaker_id, "Should set current_speaker_id"
        assert_equal 0, @conversation.round_position
        assert_equal [], @conversation.round_spoken_ids
        assert @conversation.round_queue_ids.any?, "Should build queue"
      end

      test "sets scheduling_state to ai_generating for AI speaker" do
        result = StartRound.call(conversation: @conversation, is_user_input: true)

        assert result
        assert_equal "ai_generating", @conversation.reload.scheduling_state
      end

      test "creates a queued run for AI speaker" do
        StartRound.call(conversation: @conversation, is_user_input: true)

        run = @conversation.conversation_runs.queued.first
        assert_not_nil run, "Should create a queued run"
        assert_equal @ai_character.id, run.speaker_space_membership_id
      end

      test "cancels existing queued runs" do
        # Create an existing queued run
        old_run = ConversationRun.create!(
          conversation: @conversation,
          status: "queued",
          kind: "auto_response",
          reason: "old_run",
          speaker_space_membership_id: @ai_character.id
        )

        StartRound.call(conversation: @conversation, is_user_input: true)

        old_run.reload
        assert_equal "canceled", old_run.status
        assert_equal "start_round", old_run.debug["canceled_by"]
      end

      test "returns false when no eligible candidates" do
        # Mute all AI characters
        @ai_character.update!(participation: "muted")

        result = StartRound.call(conversation: @conversation, is_user_input: true)

        assert_not result, "Should return false with no eligible candidates"
      end

      test "persists queue_ids for later use by AdvanceTurn" do
        # Add second AI for more interesting queue
        @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: characters(:ready_v3),
          position: 2
        )
        @space.update!(reply_order: "list")

        StartRound.call(conversation: @conversation, is_user_input: true)

        @conversation.reload
        assert_equal 2, @conversation.round_queue_ids.size
        assert_includes @conversation.round_queue_ids, @ai_character.id
      end

      test "generates unique round_id each time" do
        StartRound.call(conversation: @conversation, is_user_input: true)
        first_round_id = @conversation.reload.current_round_id

        # Reset state
        @conversation.update!(scheduling_state: "idle", current_round_id: nil)
        ConversationRun.where(conversation: @conversation).delete_all

        StartRound.call(conversation: @conversation, is_user_input: true)
        second_round_id = @conversation.reload.current_round_id

        assert_not_equal first_round_id, second_round_id
      end

      test "sets human_waiting state for human speaker in auto mode" do
        # Set up human with copilot persona
        @user_membership.update!(
          character: characters(:ready_v3),
          copilot_mode: "full",
          copilot_remaining_steps: 3
        )
        @ai_character.update!(participation: "muted") # Only human can respond

        @conversation.start_auto_mode!(rounds: 2)

        StartRound.call(conversation: @conversation, is_user_input: false)

        @conversation.reload
        # Human with copilot should be ai_generating (can auto respond)
        assert_equal "ai_generating", @conversation.scheduling_state
      end

      test "triggers HumanTurnTimeoutJob for human speaker in auto mode without copilot" do
        # Disable copilot so human becomes a pure human
        @user_membership.update!(copilot_mode: "none")

        # Re-enable AI so we have someone in the queue
        @ai_character.update!(participation: "active")

        @conversation.start_auto_mode!(rounds: 2)

        # StartRound should schedule an AI (first eligible)
        StartRound.call(conversation: @conversation, is_user_input: false)

        # Should create a run for AI character (human without copilot is not eligible)
        run = @conversation.conversation_runs.queued.first
        assert_not_nil run
        assert_equal @ai_character.id, run.speaker_space_membership_id
      end
    end
  end
end
