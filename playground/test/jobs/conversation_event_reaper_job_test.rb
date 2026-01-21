# frozen_string_literal: true

require "test_helper"

class ConversationEventReaperJobTest < ActiveSupport::TestCase
  test "reaps events older than retention" do
    space = Spaces::Playground.create!(name: "Event Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    now = Time.current
    old = now - 25.hours

    old_event =
      ConversationEvent.create!(
        conversation_id: conversation.id,
        space_id: space.id,
        event_name: "turn_scheduler.round_started",
        reason: "test",
        payload: { "foo" => "bar" },
        occurred_at: old,
        created_at: old,
        updated_at: old
      )

    new_event =
      ConversationEvent.create!(
        conversation_id: conversation.id,
        space_id: space.id,
        event_name: "turn_scheduler.round_started",
        reason: "test",
        payload: { "foo" => "bar" },
        occurred_at: now,
        created_at: now,
        updated_at: now
      )

    assert_difference -> { ConversationEvent.count }, -1 do
      ConversationEventReaperJob.perform_now
    end

    assert_not ConversationEvent.exists?(old_event.id)
    assert ConversationEvent.exists?(new_event.id)
  end

  test "supports custom retention" do
    space = Spaces::Playground.create!(name: "Event Space 2", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    now = Time.current
    old = now - 2.hours

    old_event =
      ConversationEvent.create!(
        conversation_id: conversation.id,
        space_id: space.id,
        event_name: "conversation_run.failed",
        reason: "test",
        payload: {},
        occurred_at: old,
        created_at: old,
        updated_at: old
      )

    assert_difference -> { ConversationEvent.count }, -1 do
      ConversationEventReaperJob.perform_now(retention: 1.hour)
    end

    assert_not ConversationEvent.exists?(old_event.id)
  end
end
