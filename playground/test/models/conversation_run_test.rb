# frozen_string_literal: true

require "test_helper"

class ConversationRunTest < ActiveSupport::TestCase
  fixtures :users

  test "enforces at most one queued run per conversation" do
    space = Spaces::Playground.create!(name: "Run Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    conversation.conversation_runs.create!(kind: "user_turn", status: "queued", reason: "test")

    assert_raises ActiveRecord::RecordNotUnique do
      conversation.conversation_runs.create!(kind: "user_turn", status: "queued", reason: "duplicate")
    end
  end

  test "enforces at most one running run per conversation" do
    space = Spaces::Playground.create!(name: "Run Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    conversation.conversation_runs.create!(kind: "user_turn", status: "running", reason: "test")

    assert_raises ActiveRecord::RecordNotUnique do
      conversation.conversation_runs.create!(kind: "user_turn", status: "running", reason: "duplicate")
    end
  end
end
