# frozen_string_literal: true

require "test_helper"

class TurnSchedulerRoundQueueManagementTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(
      name: "Round Queue Management Test Space",
      owner: @user,
      reply_order: "list",
      during_generation_user_input_policy: "queue",
      user_turn_debounce_ms: 0
    )

    @conversation = @space.conversations.create!(title: "Main", kind: "root")

    @space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    @a = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    @b = @space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v3), position: 2)

    ConversationRun.where(conversation: @conversation).delete_all
    ConversationRound.where(conversation: @conversation).delete_all
  end

  test "AppendSpeakerToRound appends to end (allows duplicates)" do
    round = create_round_with_queue([@a.id, @b.id], current_position: 0, scheduling_state: "ai_generating")
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    inserted =
      TurnScheduler::Commands::AppendSpeakerToRound.call(
        conversation: @conversation,
        speaker_id: @a.id,
        expected_round_id: round.id,
        reason: "test_append"
      )

    assert inserted

    ids_by_pos = round.participants.order(:position).pluck(:space_membership_id)
    assert_equal [@a.id, @b.id, @a.id], ids_by_pos
  end

  test "ReorderPendingParticipants reorders only upcoming portion while ai_generating (excludes current slot)" do
    round = create_round_with_queue([@a.id, @b.id, @a.id], current_position: 0, scheduling_state: "ai_generating")
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    p_b = round.participants.find_by!(position: 1)
    p_a2 = round.participants.find_by!(position: 2)

    ok =
      TurnScheduler::Commands::ReorderPendingParticipants.call(
        conversation: @conversation,
        participant_ids: [p_a2.id, p_b.id],
        expected_round_id: round.id,
        reason: "test_reorder"
      )

    assert ok

    ids_by_pos = round.participants.order(:position).pluck(:space_membership_id)
    assert_equal [@a.id, @a.id, @b.id], ids_by_pos
  end

  test "ReorderPendingParticipants rejects reorder that includes current slot while ai_generating" do
    round = create_round_with_queue([@a.id, @b.id, @a.id], current_position: 0, scheduling_state: "ai_generating")
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    p_a = round.participants.find_by!(position: 0)
    p_b = round.participants.find_by!(position: 1)
    p_a2 = round.participants.find_by!(position: 2)

    ok =
      TurnScheduler::Commands::ReorderPendingParticipants.call(
        conversation: @conversation,
        participant_ids: [p_a2.id, p_b.id, p_a.id],
        expected_round_id: round.id,
        reason: "test_reorder"
      )

    assert_not ok
  end

  test "ReorderPendingParticipants can reorder current slot when paused" do
    round = create_round_with_queue([@a.id, @b.id, @a.id], current_position: 0, scheduling_state: "paused")
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    p_a = round.participants.find_by!(position: 0)
    p_b = round.participants.find_by!(position: 1)
    p_a2 = round.participants.find_by!(position: 2)

    ok =
      TurnScheduler::Commands::ReorderPendingParticipants.call(
        conversation: @conversation,
        participant_ids: [p_b.id, p_a2.id, p_a.id],
        expected_round_id: round.id,
        reason: "test_reorder_paused"
      )

    assert ok

    ids_by_pos = round.participants.order(:position).pluck(:space_membership_id)
    assert_equal [@b.id, @a.id, @a.id], ids_by_pos
  end

  test "RemovePendingParticipant cannot remove current slot while ai_generating" do
    round = create_round_with_queue([@a.id, @b.id], current_position: 0, scheduling_state: "ai_generating")
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    current = round.participants.find_by!(position: 0)

    removed =
      TurnScheduler::Commands::RemovePendingParticipant.call(
        conversation: @conversation,
        participant_id: current.id,
        expected_round_id: round.id,
        reason: "test_remove"
      )

    assert_not removed
  end

  test "RemovePendingParticipant can remove current slot when paused (shifts queue)" do
    round = create_round_with_queue([@a.id, @b.id], current_position: 0, scheduling_state: "paused")
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    current = round.participants.find_by!(position: 0)

    removed =
      TurnScheduler::Commands::RemovePendingParticipant.call(
        conversation: @conversation,
        participant_id: current.id,
        expected_round_id: round.id,
        reason: "test_remove_paused"
      )

    assert removed

    ids_by_pos = round.participants.order(:position).pluck(:space_membership_id)
    assert_equal [@b.id], ids_by_pos
    assert_equal [0], round.participants.order(:position).pluck(:position)
  end

  test "RemovePendingParticipant finishes the round if it becomes empty" do
    round = create_round_with_queue([@a.id], current_position: 0, scheduling_state: "paused")
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    current = round.participants.find_by!(position: 0)

    removed =
      TurnScheduler::Commands::RemovePendingParticipant.call(
        conversation: @conversation,
        participant_id: current.id,
        expected_round_id: round.id,
        reason: "test_remove_last"
      )

    assert removed
    assert_equal "finished", round.reload.status
    assert_equal "round_queue_emptied", round.ended_reason
  end

  private

  def create_round_with_queue(queue_ids, current_position:, scheduling_state:)
    now = Time.current

    round = ConversationRound.create!(
      conversation: @conversation,
      status: "active",
      scheduling_state: scheduling_state,
      current_position: current_position,
      metadata: {},
      created_at: now,
      updated_at: now
    )

    queue_ids.each_with_index do |membership_id, idx|
      round.participants.create!(
        space_membership_id: membership_id,
        position: idx,
        status: "pending",
        created_at: now,
        updated_at: now
      )
    end

    round
  end
end
