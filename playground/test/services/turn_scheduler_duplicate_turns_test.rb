# frozen_string_literal: true

require "test_helper"

class TurnSchedulerDuplicateTurnsTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(
      name: "Duplicate Turns Test Space",
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

  test "SkipCurrentSpeaker skips by position when duplicate speaker ids exist" do
    round = create_round_with_queue([@a.id, @a.id, @b.id], current_position: 1)
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    advanced = TurnScheduler::Commands::SkipCurrentSpeaker.execute(
      conversation: @conversation,
      speaker_id: @a.id,
      reason: "test_skip",
      expected_round_id: round.id,
      cancel_running: false
    ).payload[:advanced]

    assert advanced

    assert_equal "pending", round.participants.find_by!(position: 0).status
    assert_equal "skipped", round.participants.find_by!(position: 1).status
  end

  test "AdvanceTurn marks spoken by current position when duplicate speaker ids exist" do
    round = create_round_with_queue([@a.id, @a.id, @b.id], current_position: 1)
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    advanced = TurnScheduler::Commands::AdvanceTurn.execute(
      conversation: @conversation,
      speaker_membership: @a,
      message_id: nil
    ).payload[:advanced]

    assert advanced

    assert_equal "pending", round.participants.find_by!(position: 0).status
    assert_equal "spoken", round.participants.find_by!(position: 1).status
  end

  test "InsertNextSpeaker inserts after current position and shifts positions (allow duplicates)" do
    round = create_round_with_queue([@a.id, @b.id], current_position: 0)
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    inserted = TurnScheduler::Commands::InsertNextSpeaker.execute(
      conversation: @conversation,
      speaker_id: @a.id,
      expected_round_id: round.id,
      reason: "test_insert"
    ).payload[:participant]

    assert inserted

    ids_by_pos = round.participants.order(:position).pluck(:space_membership_id)
    assert_equal [@a.id, @a.id, @b.id], ids_by_pos
    assert_equal [0, 1, 2], round.participants.order(:position).pluck(:position)
  end

  private

  def create_round_with_queue(queue_ids, current_position:)
    now = Time.current

    round = ConversationRound.create!(
      conversation: @conversation,
      status: "active",
      scheduling_state: "ai_generating",
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
