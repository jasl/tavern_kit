# frozen_string_literal: true

require "test_helper"

class ConversationsRoundQueueTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :admin
  end

  test "round_queue renders turbo frame content" do
    space = Spaces::Playground.create!(name: "Round Queue Render Test", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    get round_queue_conversation_url(conversation)
    assert_response :success
    assert_match(/turbo-frame[^>]+id=\"round_queue_editor\"/, response.body)
  end

  test "reorder_round_participants persists order for editable portion" do
    space = Spaces::Playground.create!(name: "Round Queue Reorder Test", owner: users(:admin), reply_order: "list")
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
    p_b = round.participants.create!(space_membership_id: b.id, position: 1, status: "pending", created_at: now, updated_at: now)
    p_a2 = round.participants.create!(space_membership_id: a.id, position: 2, status: "pending", created_at: now, updated_at: now)

    TurnScheduler::Broadcasts.stubs(:queue_updated)

    patch reorder_round_participants_conversation_url(conversation),
          params: { expected_round_id: round.id, positions: [p_a2.id, p_b.id] }
    assert_response :success

    ids_by_pos = round.participants.order(:position).pluck(:space_membership_id)
    assert_equal [a.id, a.id, b.id], ids_by_pos
  end

  test "remove_round_participant removes a pending slot and shifts positions" do
    space = Spaces::Playground.create!(name: "Round Queue Remove Test", owner: users(:admin), reply_order: "list")
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
      metadata: { "paused_reason" => "test" },
      created_at: now,
      updated_at: now
    )
    p_a = round.participants.create!(space_membership_id: a.id, position: 0, status: "pending", created_at: now, updated_at: now)
    p_b = round.participants.create!(space_membership_id: b.id, position: 1, status: "pending", created_at: now, updated_at: now)

    TurnScheduler::Broadcasts.stubs(:queue_updated)

    delete remove_round_participant_conversation_url(conversation),
           params: { expected_round_id: round.id, participant_id: p_b.id },
           as: :turbo_stream

    assert_response :success

    assert_nil round.participants.find_by(id: p_b.id)
    assert_equal 1, round.participants.count
    assert_equal p_a.id, round.participants.find_by!(position: 0).id
  end
end
