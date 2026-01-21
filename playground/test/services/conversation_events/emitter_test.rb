# frozen_string_literal: true

require "test_helper"

class ConversationEvents::EmitterTest < ActiveSupport::TestCase
  test "emits a conversation event, stores it, and notifies" do
    space = Spaces::Playground.create!(name: "Emitter Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    received = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      received << payload
    end

    now = Time.current

    ActiveSupport::Notifications.subscribed(subscriber, "turn_scheduler.round_started") do
      assert_difference -> { ConversationEvent.count }, 1 do
        event =
          ConversationEvents::Emitter.emit(
            event_name: "turn_scheduler.round_started",
            conversation: conversation,
            reason: "test",
            payload: { foo: "bar" },
            occurred_at: now
          )

        assert_not_nil event
        assert_equal conversation.id, event.conversation_id
        assert_equal space.id, event.space_id
        assert_equal "turn_scheduler.round_started", event.event_name
        assert_equal "test", event.reason
        assert_equal now.to_i, event.occurred_at.to_i
        assert_equal({ "foo" => "bar" }, event.payload)
      end
    end

    assert_equal 1, received.size
    assert_equal "turn_scheduler.round_started", received.first[:event_name]
    assert_equal conversation.id, received.first[:conversation_id]
    assert_equal space.id, received.first[:space_id]
    assert_equal "test", received.first[:reason]
  end
end
