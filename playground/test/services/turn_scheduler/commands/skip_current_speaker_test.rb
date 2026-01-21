# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Commands
    class SkipCurrentSpeakerTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space =
          Spaces::Playground.create!(
            name: "SkipCurrentSpeaker Test Space",
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
        TurnScheduler::Broadcasts.stubs(:queue_updated)
      end

      test "cancels queued run and schedules next speaker" do
        StartRound.execute(conversation: @conversation, is_user_input: true).payload[:started]

        state = TurnScheduler.state(@conversation.reload)
        assert_equal @ai1.id, state.current_speaker_id
        assert_equal 0, state.round_position

        run1 = @conversation.conversation_runs.queued.first
        assert_not_nil run1
        assert_equal @ai1.id, run1.speaker_space_membership_id

        advanced =
          SkipCurrentSpeaker.execute(
            conversation: @conversation,
            speaker_id: @ai1.id,
            reason: "test_skip"
          ).payload[:advanced]

        assert advanced

        assert_equal "canceled", run1.reload.status

        state = TurnScheduler.state(@conversation.reload)
        assert_equal @ai2.id, state.current_speaker_id
        assert_equal 1, state.round_position

        run2 = @conversation.conversation_runs.queued.first
        assert_not_nil run2
        assert_equal @ai2.id, run2.speaker_space_membership_id
      end

      test "can request cancel on running run and advance when cancel_running is true" do
        StartRound.execute(conversation: @conversation, is_user_input: true).payload[:started]

        state = TurnScheduler.state(@conversation.reload)
        assert_equal @ai1.id, state.current_speaker_id

        run1 = @conversation.conversation_runs.queued.first
        assert_not_nil run1

        now = Time.current
        run1.update!(status: "running", started_at: now, heartbeat_at: now)

        ConversationChannel.stubs(:broadcast_stream_complete)
        ConversationChannel.stubs(:broadcast_typing)

        advanced =
          SkipCurrentSpeaker.execute(
            conversation: @conversation,
            speaker_id: @ai1.id,
            reason: "test_skip_running",
            cancel_running: false
          ).payload[:advanced]

        assert_not advanced
        assert_nil run1.reload.cancel_requested_at

        advanced =
          SkipCurrentSpeaker.execute(
            conversation: @conversation,
            speaker_id: @ai1.id,
            reason: "test_skip_running",
            cancel_running: true
          ).payload[:advanced]

        assert advanced
        assert_not_nil run1.reload.cancel_requested_at

        state = TurnScheduler.state(@conversation.reload)
        assert_equal @ai2.id, state.current_speaker_id

        run2 = @conversation.conversation_runs.queued.first
        assert_not_nil run2
        assert_equal @ai2.id, run2.speaker_space_membership_id
      end
    end
  end
end
