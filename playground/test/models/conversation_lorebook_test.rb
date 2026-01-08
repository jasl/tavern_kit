# frozen_string_literal: true

require "test_helper"

class ConversationLorebookTest < ActiveSupport::TestCase
  setup do
    @conversation = conversations(:general_main)
    @lorebook = Lorebook.create!(name: "Test Lorebook")
    @lorebook2 = Lorebook.create!(name: "Test Lorebook 2")
  end

  teardown do
    @lorebook&.destroy
    @lorebook2&.destroy
  end

  test "valid with all required attributes" do
    link = ConversationLorebook.new(conversation: @conversation, lorebook: @lorebook)
    assert link.valid?
  end

  test "requires conversation" do
    link = ConversationLorebook.new(lorebook: @lorebook)
    assert_not link.valid?
    assert_includes link.errors[:conversation], "must exist"
  end

  test "requires lorebook" do
    link = ConversationLorebook.new(conversation: @conversation)
    assert_not link.valid?
    assert_includes link.errors[:lorebook], "must exist"
  end

  test "lorebook can only be attached once per conversation" do
    ConversationLorebook.create!(conversation: @conversation, lorebook: @lorebook)
    duplicate = ConversationLorebook.new(conversation: @conversation, lorebook: @lorebook)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:lorebook_id], "is already attached to this conversation"
  end

  test "enabled scope returns only enabled links" do
    enabled = ConversationLorebook.create!(conversation: @conversation, lorebook: @lorebook, enabled: true)
    disabled = ConversationLorebook.create!(conversation: @conversation, lorebook: @lorebook2, enabled: false)

    result = @conversation.conversation_lorebooks.enabled

    assert_includes result, enabled
    assert_not_includes result, disabled
  end

  test "by_priority orders by priority ascending" do
    link1 = ConversationLorebook.create!(conversation: @conversation, lorebook: @lorebook, priority: 2)
    link2 = ConversationLorebook.create!(conversation: @conversation, lorebook: @lorebook2, priority: 1)

    result = @conversation.conversation_lorebooks.by_priority.to_a

    assert_equal link2, result.first
    assert_equal link1, result.second
  end

  test "auto-sets priority for new records" do
    link1 = ConversationLorebook.create!(conversation: @conversation, lorebook: @lorebook)
    link2 = ConversationLorebook.create!(conversation: @conversation, lorebook: @lorebook2)

    assert_equal 0, link1.priority
    assert_equal 1, link2.priority
  end

  test "destroying conversation destroys conversation_lorebooks" do
    conversation = @conversation.space.conversations.create!(title: "Temp")
    ConversationLorebook.create!(conversation: conversation, lorebook: @lorebook)

    assert_difference "ConversationLorebook.count", -1 do
      conversation.destroy
    end
  end

  test "destroying lorebook destroys conversation_lorebooks" do
    lorebook = Lorebook.create!(name: "Temp Lorebook")
    ConversationLorebook.create!(conversation: @conversation, lorebook: lorebook)

    assert_difference "ConversationLorebook.count", -1 do
      lorebook.destroy
    end
  end
end
