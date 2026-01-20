# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Commands
    class AdvanceTurnTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space = Spaces::Playground.create!(
          name: "AdvanceTurn Test Space",
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
      end

      test "marks speaker as spoken in round_spoken_ids" do
        # Start a round
        StartRound.call(conversation: @conversation, is_user_input: true)

        state = TurnScheduler.state(@conversation.reload)
        assert_equal [], state.round_spoken_ids

        # Simulate AI message creation triggering advance
        AdvanceTurn.call(
          conversation: @conversation,
          speaker_membership: @ai_character1
        )

        state = TurnScheduler.state(@conversation.reload)
        assert_includes state.round_spoken_ids, @ai_character1.id
      end

      test "advances to next speaker in queue" do
        # Start round with list order (deterministic queue)
        StartRound.call(conversation: @conversation, is_user_input: true)

        state = TurnScheduler.state(@conversation.reload)
        assert_equal @ai_character1.id, state.current_speaker_id
        assert_equal 0, state.round_position

        # Simulate AI completing their turn
        ConversationRun.where(conversation: @conversation).update_all(status: "succeeded", finished_at: Time.current)

        AdvanceTurn.call(
          conversation: @conversation,
          speaker_membership: @ai_character1
        )

        state = TurnScheduler.state(@conversation.reload)
        assert_equal @ai_character2.id, state.current_speaker_id
        assert_equal 1, state.round_position
      end

      test "handles round completion and resets to idle without auto mode" do
        # Start round with list order
        StartRound.call(conversation: @conversation, is_user_input: true)

        # Advance through all speakers
        ConversationRun.where(conversation: @conversation).update_all(status: "succeeded", finished_at: Time.current)
        AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai_character1)

        ConversationRun.where(conversation: @conversation).update_all(status: "succeeded", finished_at: Time.current)
        AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai_character2)

        assert TurnScheduler.state(@conversation.reload).idle?
      end

      test "starts new round after completion when auto mode is active" do
        @conversation.start_auto_without_human!(rounds: 3)

        StartRound.call(conversation: @conversation, is_user_input: false)
        initial_round_id = TurnScheduler.state(@conversation.reload).current_round_id

        # Complete all speakers
        ConversationRun.where(conversation: @conversation).update_all(status: "succeeded", finished_at: Time.current)
        AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai_character1)

        ConversationRun.where(conversation: @conversation).update_all(status: "succeeded", finished_at: Time.current)
        AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai_character2)

        state = TurnScheduler.state(@conversation.reload)
        assert_not_equal initial_round_id, state.current_round_id
        assert_not state.idle?
      end

      test "decrements auto_without_human_remaining_rounds on round completion" do
        @conversation.start_auto_without_human!(rounds: 3)
        assert_equal 3, @conversation.auto_without_human_remaining_rounds

        StartRound.call(conversation: @conversation, is_user_input: false)

        # Complete all speakers
        ConversationRun.where(conversation: @conversation).update_all(status: "succeeded", finished_at: Time.current)
        AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai_character1)

        ConversationRun.where(conversation: @conversation).update_all(status: "succeeded", finished_at: Time.current)
        AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai_character2)

        @conversation.reload
        assert_equal 2, @conversation.auto_without_human_remaining_rounds
      end

      test "increments turns_count" do
        initial_count = @conversation.turns_count

        StartRound.call(conversation: @conversation, is_user_input: true)
        AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai_character1)

        assert_equal initial_count + 1, @conversation.reload.turns_count
      end

      test "uses with_lock for concurrency safety" do
        StartRound.call(conversation: @conversation, is_user_input: true)

        # Mock to verify with_lock is called
        lock_called = false
        @conversation.define_singleton_method(:with_lock) do |&block|
          lock_called = true
          block.call
        end

        AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai_character1)

        assert lock_called, "Should use with_lock for concurrency safety"
      end

      test "starts round from idle when user message triggers" do
        assert TurnScheduler.state(@conversation).idle?

        # Create a user message
        message = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello!"
        )

        AdvanceTurn.call(
          conversation: @conversation,
          speaker_membership: @user_membership,
          message_id: message.id
        )

        state = TurnScheduler.state(@conversation.reload)
        assert_not state.idle?
        assert_not_nil state.current_round_id
      end

      test "does not start a new round when scheduler is failed (requires explicit recovery)" do
        StartRound.call(conversation: @conversation, is_user_input: true)

        failed_round = @conversation.conversation_rounds.find_by!(status: "active")
        failed_round.update!(scheduling_state: "failed")
        @conversation.conversation_runs.queued.update_all(status: "canceled", finished_at: Time.current)

        message = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "New question after failure"
        )

        advanced =
          AdvanceTurn.call(
            conversation: @conversation,
            speaker_membership: @user_membership,
            message_id: message.id
          )

        assert_not advanced

        state = TurnScheduler.state(@conversation.reload)
        assert state.failed?
        assert_equal failed_round.id, state.current_round_id
      end

      test "does not auto-advance when scheduler is failed" do
        StartRound.call(conversation: @conversation, is_user_input: true)

        failed_round = @conversation.conversation_rounds.find_by!(status: "active")
        failed_round.update!(scheduling_state: "failed")
        @conversation.conversation_runs.queued.update_all(status: "canceled", finished_at: Time.current)

        message = @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "Manual assistant message"
        )

        advanced =
          AdvanceTurn.call(
            conversation: @conversation,
            speaker_membership: @ai_character1,
            message_id: message.id
          )

        assert_not advanced

        state = TurnScheduler.state(@conversation.reload)
        assert state.failed?
        assert_equal failed_round.id, state.current_round_id
        assert_equal 0, state.round_position
        assert_equal @ai_character1.id, state.current_speaker_id
      end

      test "records the message but does not schedule the next speaker when paused" do
        StartRound.call(conversation: @conversation, is_user_input: true)

        round = @conversation.conversation_rounds.find_by!(status: "active")
        @conversation.conversation_runs.queued.update_all(status: "canceled", finished_at: Time.current)
        round.update!(scheduling_state: "paused")

        advanced =
          AdvanceTurn.call(
            conversation: @conversation,
            speaker_membership: @ai_character1
          )

        assert advanced

        round.reload
        assert_equal "paused", round.scheduling_state
        assert_equal 1, round.current_position
        assert_empty @conversation.conversation_runs.queued
      end

      test "does not start round from idle for assistant message without auto scheduling" do
        assert TurnScheduler.state(@conversation).idle?

        message = @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "Hello!"
        )

        AdvanceTurn.call(
          conversation: @conversation,
          speaker_membership: @ai_character1,
          message_id: message.id
        )

        assert TurnScheduler.state(@conversation.reload).idle?
      end

      test "does not advance the active round for message from an independent run (no conversation_round_id)" do
        StartRound.call(conversation: @conversation, is_user_input: true)

        before_state = TurnScheduler.state(@conversation.reload)
        assert_equal @ai_character1.id, before_state.current_speaker_id
        assert_equal 0, before_state.round_position

        # Simulate a force_talk run creating a message while a scheduler round is active.
        # This run is independent (no conversation_round_id) and must NOT mutate the round.
        force_talk_run = ConversationRun.create!(
          conversation: @conversation,
          status: "succeeded",
          kind: "force_talk",
          reason: "force_talk",
          speaker_space_membership_id: @ai_character2.id,
          finished_at: Time.current,
          debug: { "trigger" => "force_talk" }
        )

        @conversation.messages.create!(
          space_membership: @ai_character2,
          role: "assistant",
          content: "Force talk message",
          conversation_run: force_talk_run,
          generation_status: "succeeded"
        )

        state = TurnScheduler.state(@conversation.reload)
        assert_equal before_state.current_round_id, state.current_round_id
        assert_equal @ai_character1.id, state.current_speaker_id
        assert_equal 0, state.round_position

        active_round = @conversation.conversation_rounds.find_by!(status: "active")
        participant = active_round.participants.find_by!(space_membership_id: @ai_character2.id)
        assert_not participant.spoken?
      end

      test "skips non-respondable speakers when advancing" do
        # Mute second AI
        @ai_character2.update!(participation: "muted")

        StartRound.call(conversation: @conversation, is_user_input: true)

        ConversationRun.where(conversation: @conversation).update_all(status: "succeeded", finished_at: Time.current)
        AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai_character1)

        # Should complete round since second AI is muted
        assert TurnScheduler.state(@conversation.reload).idle?
      end

      test "uses persisted round_queue_ids for advancement" do
        StartRound.call(conversation: @conversation, is_user_input: true)

        original_queue = TurnScheduler.state(@conversation.reload).round_queue_ids.dup

        # Simulate a membership change mid-round (shouldn't affect current round)
        @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: Character.create!(
            name: "New Char",
            personality: "New",
            data: { "name" => "New Char" },
            spec_version: 2,
            file_sha256: "new_#{SecureRandom.hex(8)}",
            status: "ready",
            visibility: "private"
          ),
          position: 3
        )

        ConversationRun.where(conversation: @conversation).update_all(status: "succeeded", finished_at: Time.current)
        AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai_character1)

        # Queue should not have changed during the round
        assert_equal original_queue, TurnScheduler.state(@conversation.reload).round_queue_ids
      end
    end
  end
end
