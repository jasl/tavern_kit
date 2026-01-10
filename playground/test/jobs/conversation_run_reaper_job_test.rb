# frozen_string_literal: true

require "test_helper"

class ConversationRunReaperJobTest < ActiveSupport::TestCase
  setup do
    clear_enqueued_jobs

    ConversationChannel.stubs(:broadcast_stream_complete)
    Message.any_instance.stubs(:broadcast_update)
  end

  test "reaps a stale running run, fixes placeholder message, and kicks queued run" do
    space = Spaces::Playground.create!(name: "Reaper Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    now = Time.current
    stale_at = now - ConversationRun::STALE_TIMEOUT - 1.second

    stale_run =
      conversation.conversation_runs.create!(
        kind: "user_turn",
        status: "running",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        started_at: stale_at,
        heartbeat_at: stale_at
      )

    placeholder =
      conversation.messages.create!(
        space_membership: speaker,
        role: "assistant",
        content: nil,
        conversation_run: stale_run,
        generation_status: "generating"
      )

    queued_run =
      conversation.conversation_runs.create!(
        kind: "user_turn",
        status: "queued",
        reason: "queued_after_stale",
        speaker_space_membership_id: speaker.id,
        run_after: now
      )

    expected_user_message =
      I18n.t(
        "messages.generation_errors.stale_running_run",
        default: "Generation timed out. Please try again."
      )

    assert_enqueued_with(job: ConversationRunJob, args: [queued_run.id]) do
      ConversationRunReaperJob.perform_now(stale_run.id)
    end

    stale_run.reload
    assert_equal "failed", stale_run.status
    assert_equal "stale_running_run", stale_run.error["code"]

    placeholder.reload
    assert_equal expected_user_message, placeholder.content
    assert_equal "failed", placeholder.generation_status
    assert_equal expected_user_message, placeholder.metadata["error"]
  end

  test "sets cancel_requested_at when marking stale run as failed" do
    space = Spaces::Playground.create!(name: "Cancel Flag Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)

    now = Time.current
    stale_at = now - ConversationRun::STALE_TIMEOUT - 1.second

    stale_run =
      conversation.conversation_runs.create!(
        kind: "user_turn",
        status: "running",
        reason: "test",
        speaker_space_membership_id: speaker.id,
        started_at: stale_at,
        heartbeat_at: stale_at,
        cancel_requested_at: nil
      )

    assert_nil stale_run.cancel_requested_at

    ConversationRunReaperJob.perform_now(stale_run.id)

    stale_run.reload
    assert_equal "failed", stale_run.status
    assert_not_nil stale_run.cancel_requested_at, "cancel_requested_at should be set when stale run is marked failed"
    assert stale_run.cancel_requested?, "cancel_requested? should return true"
  end
end
