# frozen_string_literal: true

require "test_helper"

class ConversationRunTest < ActiveSupport::TestCase
  fixtures :users

  test "enforces at most one queued run per conversation" do
    space = Spaces::Playground.create!(name: "Run Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    ConversationRun::AutoTurn.create!(conversation: conversation, status: "queued", reason: "test")

    assert_raises ActiveRecord::RecordNotUnique do
      ConversationRun::AutoTurn.create!(conversation: conversation, status: "queued", reason: "duplicate")
    end
  end

  test "enforces at most one running run per conversation" do
    space = Spaces::Playground.create!(name: "Run Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    ConversationRun::AutoTurn.create!(conversation: conversation, status: "running", reason: "test")

    assert_raises ActiveRecord::RecordNotUnique do
      ConversationRun::AutoTurn.create!(conversation: conversation, status: "running", reason: "duplicate")
    end
  end
end
