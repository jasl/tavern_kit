# frozen_string_literal: true

require "test_helper"

class ConversationEvents::Queries::EventStreamTest < ActiveSupport::TestCase
  test "returns recent events for a conversation" do
    space = Spaces::Playground.create!(name: "Stream Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    now = Time.current
    earlier = now - 1.minute

    older =
      ConversationEvent.create!(
        conversation_id: conversation.id,
        space_id: space.id,
        event_name: "turn_scheduler.round_started",
        payload: {},
        occurred_at: earlier
      )

    newer =
      ConversationEvent.create!(
        conversation_id: conversation.id,
        space_id: space.id,
        event_name: "turn_scheduler.round_paused",
        payload: {},
        occurred_at: now
      )

    events = ConversationEvents::Queries::EventStream.execute(conversation: conversation, limit: 50)

    assert_equal [newer.id, older.id], events.map(&:id)
  end

  test "filters by scope" do
    space = Spaces::Playground.create!(name: "Stream Space Scope", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    scheduler_event =
      ConversationEvent.create!(
        conversation_id: conversation.id,
        space_id: space.id,
        event_name: "turn_scheduler.round_started",
        payload: {},
        occurred_at: Time.current - 2.seconds
      )

    run_event =
      ConversationEvent.create!(
        conversation_id: conversation.id,
        space_id: space.id,
        event_name: "conversation_run.failed",
        payload: {},
        occurred_at: Time.current - 1.second
      )

    ConversationEvent.create!(
      conversation_id: conversation.id,
      space_id: space.id,
      event_name: "other.event",
      payload: {},
      occurred_at: Time.current
    )

    scheduler_events =
      ConversationEvents::Queries::EventStream.execute(
        conversation: conversation,
        scope: "scheduler",
        limit: 50
      )
    assert_equal [scheduler_event.id], scheduler_events.map(&:id)

    run_events =
      ConversationEvents::Queries::EventStream.execute(
        conversation: conversation,
        scope: "run",
        limit: 50
      )
    assert_equal [run_event.id], run_events.map(&:id)
  end

  test "filters by round/run ids" do
    space = Spaces::Playground.create!(name: "Stream Space 2", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    round_id = SecureRandom.uuid
    run_id = SecureRandom.uuid

    matching =
      ConversationEvent.create!(
        conversation_id: conversation.id,
        space_id: space.id,
        event_name: "conversation_run.failed",
        conversation_round_id: round_id,
        conversation_run_id: run_id,
        payload: {},
        occurred_at: Time.current
      )

    ConversationEvent.create!(
      conversation_id: conversation.id,
      space_id: space.id,
      event_name: "conversation_run.failed",
      conversation_round_id: SecureRandom.uuid,
      conversation_run_id: run_id,
      payload: {},
      occurred_at: Time.current
    )

    events =
      ConversationEvents::Queries::EventStream.execute(
        conversation: conversation,
        conversation_round_id: round_id,
        conversation_run_id: run_id,
        limit: 50
      )

    assert_equal [matching.id], events.map(&:id)
  end

  test "clamps limit" do
    space = Spaces::Playground.create!(name: "Stream Space 3", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    ConversationEvent.create!(
      conversation_id: conversation.id,
      space_id: space.id,
      event_name: "turn_scheduler.round_started",
      payload: {},
      occurred_at: Time.current
    )

    events = ConversationEvents::Queries::EventStream.execute(conversation: conversation, limit: 0)
    assert_equal 1, events.size
  end
end
