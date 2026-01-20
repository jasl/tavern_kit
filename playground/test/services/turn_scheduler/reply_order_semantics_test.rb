# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  class ReplyOrderSemanticsTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @user = users(:admin)
      @space =
        Spaces::Playground.create!(
          name: "ReplyOrderSemantics Test Space",
          owner: @user,
          reply_order: "list",
          allow_self_responses: false,
          user_turn_debounce_ms: 0
        )
      @conversation = @space.conversations.create!(title: "Main")

      @human =
        @space.space_memberships.create!(
          kind: "human",
          role: "owner",
          user: @user,
          position: 0
        )

      # Two AI participants (group chat baseline).
      @ai1 =
        @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: characters(:ready_v2),
          position: 1,
          talkativeness_factor: 1.0
        )
      @ai2 =
        @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: characters(:ready_v3),
          position: 2,
          talkativeness_factor: 1.0
        )

      ConversationRun.where(conversation: @conversation).delete_all
      clear_enqueued_jobs
      clear_performed_jobs
    end

    test "ActivatedQueue sizes match reply_order semantics" do
      @space.update!(reply_order: "list")
      queue =
        Queries::ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: nil,
          is_user_input: true,
          rng: Random.new(42)
        )
      assert_equal [@ai1.id, @ai2.id], queue.map(&:id)

      @space.update!(reply_order: "pooled")
      queue =
        Queries::ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: nil,
          is_user_input: true,
          rng: Random.new(42)
        )
      assert_equal 1, queue.size
      assert_includes [@ai1.id, @ai2.id], queue.first.id

      @space.update!(reply_order: "natural")
      queue =
        Queries::ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: nil,
          is_user_input: true,
          rng: Random.new(42)
        )
      assert_equal [@ai1.id, @ai2.id].sort, queue.map(&:id).sort

      @space.update!(reply_order: "manual")
      queue =
        Queries::ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: nil,
          is_user_input: true,
          rng: Random.new(42)
        )
      assert_empty queue
    end

    test "StartRound persists queue into round participants and schedules first run" do
      {
        "list" => 2,
        "natural" => 2,
        "pooled" => 1,
      }.each do |reply_order, expected_queue_size|
        @space.update!(reply_order: reply_order)
        clear_enqueued_jobs

        conversation = @space.conversations.create!(title: "StartRound #{reply_order}")

        started =
          Commands::StartRound.call(
            conversation: conversation,
            trigger_message: nil,
            is_user_input: true,
            rng: Random.new(42)
          )

        assert started

        state = TurnScheduler.state(conversation.reload)
        assert_equal "ai_generating", state.scheduling_state
        assert_equal expected_queue_size, state.round_queue_ids.size

        round = conversation.conversation_rounds.find_by!(status: "active")
        assert_equal expected_queue_size, round.participants.count

        run = conversation.conversation_runs.queued.first
        assert_not_nil run
        assert_equal state.current_round_id, run.conversation_round_id
        assert_equal state.current_speaker_id, run.speaker_space_membership_id

        assert_enqueued_jobs 1, only: ConversationRunJob
      end
    end

    test "StartRound does not auto-start on real user input when reply_order=manual" do
      @space.update!(reply_order: "manual")
      started =
        Commands::StartRound.call(
          conversation: @conversation,
          trigger_message: nil,
          is_user_input: true,
          rng: Random.new(42)
        )

      assert_not started
      assert_nil @conversation.conversation_rounds.find_by(status: "active")
      assert_empty @conversation.conversation_runs
    end

    test "AdvanceTurn follows persisted queue and returns to idle (list)" do
      @space.update!(reply_order: "list")
      Commands::StartRound.call(conversation: @conversation, trigger_message: nil, is_user_input: true, rng: Random.new(42))
      state = TurnScheduler.state(@conversation.reload)
      assert_equal [@ai1.id, @ai2.id], state.round_queue_ids
      assert_equal @ai1.id, state.current_speaker_id

      # Speaker 1 completes
      @conversation.conversation_runs.update_all(status: "succeeded", finished_at: Time.current)
      Commands::AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai1)

      state = TurnScheduler.state(@conversation.reload)
      assert_equal @ai2.id, state.current_speaker_id
      assert_equal 1, state.round_position
      assert_equal @ai2.id, @conversation.conversation_runs.queued.pick(:speaker_space_membership_id)

      # Speaker 2 completes -> idle
      @conversation.conversation_runs.update_all(status: "succeeded", finished_at: Time.current)
      Commands::AdvanceTurn.call(conversation: @conversation, speaker_membership: @ai2)

      state = TurnScheduler.state(@conversation.reload)
      assert state.idle?
      assert_nil @conversation.conversation_rounds.find_by(status: "active")
    end

    test "AdvanceTurn does not start a round from idle on user message when reply_order=manual" do
      @space.update!(reply_order: "manual")

      msg = @conversation.messages.create!(space_membership: @human, role: "user", content: "Hello manual")
      assert TurnScheduler.state(@conversation).idle?

      advanced = Commands::AdvanceTurn.call(conversation: @conversation, speaker_membership: @human, message_id: msg.id)

      assert_not advanced
      assert TurnScheduler.state(@conversation.reload).idle?
      assert_nil @conversation.conversation_rounds.find_by(status: "active")
    end
  end
end
