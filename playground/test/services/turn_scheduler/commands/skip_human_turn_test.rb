# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Commands
    class SkipHumanTurnTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space = Spaces::Playground.create!(
          name: "SkipHumanTurn Test Space",
          owner: @user,
          reply_order: "list"
        )
        @conversation = @space.conversations.create!(title: "Main")
        @user_membership = @space.space_memberships.create!(
          kind: "human",
          role: "owner",
          user: @user,
          position: 0
        )
        @ai_character1 = @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: characters(:ready_v2),
          position: 1
        )
        @ai_character2 = @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: characters(:ready_v3),
          position: 2
        )

        ConversationRun.where(conversation: @conversation).delete_all

        # Enable auto mode and set up a round with human as current speaker
        @conversation.start_auto_mode!(rounds: 3)

        # Manually set up round state with human as current speaker
        @round_id = SecureRandom.uuid
        @conversation.update!(
          scheduling_state: "human_waiting",
          current_round_id: @round_id,
          current_speaker_id: @user_membership.id,
          round_position: 0,
          round_spoken_ids: [],
          round_queue_ids: [@user_membership.id, @ai_character1.id, @ai_character2.id]
        )

        # Create the human_turn run
        @human_run = ConversationRun.create!(
          conversation: @conversation,
          status: "queued",
          kind: "human_turn",
          reason: "human_turn",
          speaker_space_membership_id: @user_membership.id,
          debug: { "round_id" => @round_id }
        )
      end

      test "skips human turn when conditions are met" do
        result = SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        assert result, "Should return true on successful skip"
      end

      test "advances to next speaker after skip" do
        SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        @conversation.reload
        assert_equal @ai_character1.id, @conversation.current_speaker_id
        assert_equal 1, @conversation.round_position
      end

      test "marks human_turn run as skipped" do
        SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        @human_run.reload
        assert_equal "skipped", @human_run.status
        assert_equal "timeout", @human_run.debug["skipped_reason"]
      end

      test "returns false if not in same round" do
        result = SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: "different-round-id"
        )

        assert_not result, "Should return false for mismatched round_id"
      end

      test "returns false if auto mode is disabled" do
        @conversation.stop_auto_mode!
        @conversation.update!(scheduling_state: "human_waiting")

        result = SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        assert_not result
      end

      test "returns false if human has already spoken" do
        @conversation.update!(round_spoken_ids: [@user_membership.id])

        result = SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        assert_not result
      end

      test "returns false if different speaker is current" do
        @conversation.update!(current_speaker_id: @ai_character1.id)

        result = SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        assert_not result
      end

      test "returns false if idle" do
        @conversation.update!(scheduling_state: "idle")

        result = SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        assert_not result
      end

      test "handles round completion when last in queue" do
        # Set human as last speaker
        @conversation.update!(
          round_position: 2,
          current_speaker_id: @user_membership.id,
          round_queue_ids: [@ai_character1.id, @ai_character2.id, @user_membership.id],
          round_spoken_ids: [@ai_character1.id, @ai_character2.id]
        )

        SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        @conversation.reload
        # Should decrement rounds and possibly start new round
        assert @conversation.auto_mode_remaining_rounds < 3
      end

      test "uses persisted round_queue_ids not recalculated queue" do
        # Store original queue
        original_queue = @conversation.round_queue_ids.dup

        # Add new member mid-round (should not affect current round)
        @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: Character.create!(
            name: "Mid-Round Char",
            personality: "Test",
            data: { "name" => "Mid-Round Char" },
            spec_version: 2,
            file_sha256: "midround_#{SecureRandom.hex(8)}",
            status: "ready",
            visibility: "private"
          ),
          position: 3
        )

        SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        @conversation.reload
        # Queue should still be the original
        assert_equal original_queue, @conversation.round_queue_ids
        # Next speaker should be from original queue
        assert_equal @ai_character1.id, @conversation.current_speaker_id
      end

      test "creates new run for AI speaker after skip" do
        SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        # Should have a new queued run for the AI
        ai_run = ConversationRun.where(
          conversation: @conversation,
          speaker_space_membership_id: @ai_character1.id
        ).queued.first

        assert_not_nil ai_run, "Should create run for next AI speaker"
      end

      test "idempotent - second call has no effect" do
        # First skip
        SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        @conversation.reload
        # After first skip, current_speaker should have changed to AI
        assert_equal @ai_character1.id, @conversation.current_speaker_id

        # Second skip - should fail because current_speaker is no longer the human
        result = SkipHumanTurn.call(
          conversation: @conversation,
          membership_id: @user_membership.id,
          round_id: @round_id
        )

        assert_not result, "Second skip should fail (current_speaker changed)"
      end
    end
  end
end
