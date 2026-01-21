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

        response =
          StartRound.execute(
            conversation: @conversation,
            is_user_input: true,
            rng: rng
          )

        assert response.payload[:started], "Should return started=true on success"

        state = TurnScheduler.state(@conversation.reload)
        assert_not_nil state.current_round_id, "Should set round_id"
        assert_not_nil state.current_speaker_id, "Should set current_speaker_id"
        assert_equal 0, state.round_position
        assert_equal [], state.round_spoken_ids
        assert state.round_queue_ids.any?, "Should build queue"
      end

      test "sets scheduling_state to ai_generating for AI speaker" do
        response = StartRound.execute(conversation: @conversation, is_user_input: true)

        assert response.payload[:started]
        assert_equal "ai_generating", TurnScheduler.state(@conversation.reload).scheduling_state
      end

      test "creates a queued run for AI speaker" do
        StartRound.execute(conversation: @conversation, is_user_input: true)

        run = @conversation.conversation_runs.queued.first
        assert_not_nil run, "Should create a queued run"
        assert_equal @ai_character.id, run.speaker_space_membership_id
        assert_not_nil run.conversation_round_id
      end

      test "applies user_turn_debounce_ms to first scheduled run on real user input" do
        @space.update!(user_turn_debounce_ms: 800)

        travel_to Time.current.change(usec: 0) do
          StartRound.execute(conversation: @conversation, is_user_input: true)

          run = @conversation.conversation_runs.queued.first
          assert_not_nil run
          assert_in_delta Time.current + 0.8, run.run_after, 0.1
        end
      end

      test "does not apply user_turn_debounce_ms when not user input" do
        @space.update!(user_turn_debounce_ms: 800)

        travel_to Time.current.change(usec: 0) do
          StartRound.execute(conversation: @conversation, is_user_input: false)

          run = @conversation.conversation_runs.queued.first
          assert_not_nil run
          assert_in_delta Time.current, run.run_after, 0.1
        end
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

        StartRound.execute(conversation: @conversation, is_user_input: true)

        old_run.reload
        assert_equal "canceled", old_run.status
        assert_equal "start_round", old_run.debug["canceled_by"]
      end

      test "returns false when no eligible candidates" do
        # Mute all AI characters
        @ai_character.update!(participation: "muted")

        response = StartRound.execute(conversation: @conversation, is_user_input: true)

        assert_not response.payload[:started], "Should return started=false with no eligible candidates"
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

        StartRound.execute(conversation: @conversation, is_user_input: true)

        state = TurnScheduler.state(@conversation.reload)
        assert_equal 2, state.round_queue_ids.size
        assert_includes state.round_queue_ids, @ai_character.id
      end

      test "generates unique round_id each time" do
        StartRound.execute(conversation: @conversation, is_user_input: true)
        first_round_id = TurnScheduler.state(@conversation.reload).current_round_id

        ConversationRun.where(conversation: @conversation).delete_all

        StartRound.execute(conversation: @conversation, is_user_input: true)
        second_round_id = TurnScheduler.state(@conversation.reload).current_round_id

        assert_not_equal first_round_id, second_round_id
        assert_equal "superseded", ConversationRound.find(first_round_id).status
      end

      test "sets ai_generating state for auto user speaker in auto without human" do
        # Set up human with auto persona
        @user_membership.update!(
          character: characters(:ready_v3),
          auto: "auto",
          auto_remaining_steps: 3
        )
        @ai_character.update!(participation: "muted") # Only human can respond

        @conversation.start_auto_without_human!(rounds: 2)

        StartRound.execute(conversation: @conversation, is_user_input: false)

        state = TurnScheduler.state(@conversation.reload)
        assert_equal "ai_generating", state.scheduling_state

        run = @conversation.conversation_runs.queued.first
        assert_not_nil run
        assert_equal "auto_user_response", run.kind
      end

      test "does not schedule pure humans (auto disabled)" do
        # Disable auto so human becomes a pure human
        @user_membership.update!(auto: "none")

        # Re-enable AI so we have someone in the queue
        @ai_character.update!(participation: "active")

        @conversation.start_auto_without_human!(rounds: 2)

        # StartRound should schedule an AI (first eligible)
        StartRound.execute(conversation: @conversation, is_user_input: false)

        # Should create a run for AI character (human without Auto is not eligible)
        run = @conversation.conversation_runs.queued.first
        assert_not_nil run
        assert_equal @ai_character.id, run.speaker_space_membership_id
      end
    end
  end
end
