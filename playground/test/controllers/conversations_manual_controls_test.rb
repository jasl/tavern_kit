# frozen_string_literal: true

require "test_helper"

class ConversationsManualControlsTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :admin
  end

  test "stop pauses the active round with user_stop reason" do
    space = Spaces::Playground.create!(name: "Stop Pauses Round", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    now = Time.current
    round = ConversationRound.create!(
      conversation: conversation,
      status: "active",
      scheduling_state: "ai_generating",
      current_position: 0,
      metadata: {},
      created_at: now,
      updated_at: now
    )
    round.participants.create!(space_membership_id: ai.id, position: 0, status: "pending", created_at: now, updated_at: now)

    run = ConversationRun.create!(
      kind: "auto_response",
      conversation: conversation,
      conversation_round_id: round.id,
      status: "running",
      reason: "test",
      speaker_space_membership_id: ai.id,
      started_at: now
    )

    TurnScheduler::Broadcasts.stubs(:queue_updated)
    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_typing)

    post stop_conversation_url(conversation)
    assert_response :no_content

    round.reload
    assert_equal "paused", round.scheduling_state
    assert_equal "user_stop", round.metadata["paused_reason"]

    run.reload
    assert_not_nil run.cancel_requested_at

    # Once the run is gone, health should stay healthy (paused), not idle_unexpected.
    run.update!(status: "canceled", finished_at: Time.current)
    health = Conversations::HealthChecker.check(conversation)
    assert_equal "healthy", health[:status]
    assert_equal "user_stop", health.dig(:details, :paused_reason)
  end

  test "retry_current_speaker schedules a new run when paused" do
    space = Spaces::Playground.create!(name: "Retry Paused", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    now = Time.current
    round = ConversationRound.create!(
      conversation: conversation,
      status: "active",
      scheduling_state: "paused",
      current_position: 0,
      metadata: { "paused_reason" => "user_stop" },
      created_at: now,
      updated_at: now
    )
    round.participants.create!(space_membership_id: ai.id, position: 0, status: "pending", created_at: now, updated_at: now)

    TurnScheduler::Broadcasts.stubs(:queue_updated)

    post retry_current_speaker_conversation_url(conversation), as: :turbo_stream
    assert_response :success

    round.reload
    assert_equal "ai_generating", round.scheduling_state

    queued = conversation.conversation_runs.queued.first
    assert queued
    assert_equal round.id, queued.conversation_round_id
    assert_equal ai.id, queued.speaker_space_membership_id
  end

  test "skip_current_speaker advances to next speaker when paused" do
    space = Spaces::Playground.create!(name: "Skip Paused", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    a = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    b = space.space_memberships.find_by!(character: characters(:ready_v3), kind: "character")

    now = Time.current
    round = ConversationRound.create!(
      conversation: conversation,
      status: "active",
      scheduling_state: "paused",
      current_position: 0,
      metadata: { "paused_reason" => "user_stop" },
      created_at: now,
      updated_at: now
    )
    round.participants.create!(space_membership_id: a.id, position: 0, status: "pending", created_at: now, updated_at: now)
    round.participants.create!(space_membership_id: b.id, position: 1, status: "pending", created_at: now, updated_at: now)

    TurnScheduler::Broadcasts.stubs(:queue_updated)
    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_typing)

    post skip_current_speaker_conversation_url(conversation), as: :turbo_stream
    assert_response :success

    round.reload
    assert_equal 1, round.current_position

    assert_equal "skipped", round.participants.find_by!(position: 0).status
    assert_equal "pending", round.participants.find_by!(position: 1).status

    queued = conversation.conversation_runs.queued.first
    assert queued
    assert_equal b.id, queued.speaker_space_membership_id
    assert_equal round.id, queued.conversation_round_id
  end

  test "add_speaker starts a one-slot round when idle" do
    space = Spaces::Playground.create!(name: "Add Speaker Idle", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    TurnScheduler::Broadcasts.stubs(:queue_updated)

    post add_speaker_conversation_url(conversation), params: { speaker_id: ai.id }, as: :turbo_stream
    assert_response :success

    round = conversation.conversation_rounds.find_by!(status: "active")
    assert_equal "ai_generating", round.scheduling_state
    assert_equal [ai.id], round.participants.order(:position).pluck(:space_membership_id)

    queued = conversation.conversation_runs.queued.first
    assert queued
    assert_equal round.id, queued.conversation_round_id
    assert_equal ai.id, queued.speaker_space_membership_id
  end

  test "add_speaker appends speaker to end of active round (allows duplicates)" do
    space = Spaces::Playground.create!(name: "Add Speaker Active", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    a = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    b = space.space_memberships.find_by!(character: characters(:ready_v3), kind: "character")

    now = Time.current
    round = ConversationRound.create!(
      conversation: conversation,
      status: "active",
      scheduling_state: "ai_generating",
      current_position: 0,
      metadata: {},
      created_at: now,
      updated_at: now
    )
    round.participants.create!(space_membership_id: a.id, position: 0, status: "pending", created_at: now, updated_at: now)
    round.participants.create!(space_membership_id: b.id, position: 1, status: "pending", created_at: now, updated_at: now)

    TurnScheduler::Broadcasts.stubs(:queue_updated)

    post add_speaker_conversation_url(conversation), params: { speaker_id: a.id }, as: :turbo_stream
    assert_response :success

    ids_by_pos = round.participants.order(:position).pluck(:space_membership_id)
    assert_equal [a.id, b.id, a.id], ids_by_pos
    assert_equal [0, 1, 2], round.participants.order(:position).pluck(:position)
  end
end
