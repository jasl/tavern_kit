# frozen_string_literal: true

require "test_helper"

class Conversations::LorebooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :member

    @own_conversation = conversations(:ai_chat_main)  # owned by member
    @own_lorebook = Lorebook.create!(name: "My Lorebook")

    @victim_conversation = conversations(:general_main)  # owned by admin
    @victim_lorebook = Lorebook.create!(name: "Victim Lorebook")
  end

  teardown do
    @own_lorebook&.destroy
    @victim_lorebook&.destroy
  end

  # === Authorization Tests ===

  test "index redirects for conversations outside current user's spaces" do
    get conversation_lorebooks_url(@victim_conversation)

    assert_response :not_found
  end

  test "create does not attach lorebooks for conversations outside current user's spaces" do
    assert_no_difference "ConversationLorebook.count" do
      post conversation_lorebooks_url(@victim_conversation), params: {
        conversation_lorebook: {
          lorebook_id: @victim_lorebook.id,
          enabled: true,
        },
      }
    end

    assert_response :not_found
  end

  test "destroy does not detach lorebooks for conversations outside current user's spaces" do
    victim_attachment =
      ConversationLorebook.create!(
        conversation: @victim_conversation,
        lorebook: @victim_lorebook,
        enabled: true
      )

    assert_no_difference "ConversationLorebook.count" do
      delete conversation_lorebook_url(@victim_conversation, victim_attachment)
    end

    assert_response :not_found
    assert ConversationLorebook.exists?(victim_attachment.id)
  end

  test "toggle does not modify attachments for conversations outside current user's spaces" do
    victim_attachment =
      ConversationLorebook.create!(
        conversation: @victim_conversation,
        lorebook: @victim_lorebook,
        enabled: true
      )

    patch toggle_conversation_lorebook_url(@victim_conversation, victim_attachment)

    assert_response :not_found

    victim_attachment.reload
    assert_equal true, victim_attachment.enabled
  end

  # === CRUD Tests ===

  test "index renders lorebooks list" do
    ConversationLorebook.create!(conversation: @own_conversation, lorebook: @own_lorebook)

    get conversation_lorebooks_url(@own_conversation)

    assert_response :success
    assert_select "turbo-frame#conversation_lorebooks"
  end

  test "create attaches a lorebook to conversation" do
    assert_difference "ConversationLorebook.count", 1 do
      post conversation_lorebooks_url(@own_conversation), params: {
        conversation_lorebook: {
          lorebook_id: @own_lorebook.id,
          enabled: true,
        },
      }
    end

    assert_redirected_to conversation_lorebooks_url(@own_conversation)

    link = @own_conversation.conversation_lorebooks.last
    assert_equal @own_lorebook.id, link.lorebook_id
    assert link.enabled
  end

  test "create with turbo_stream replaces frame" do
    assert_difference "ConversationLorebook.count", 1 do
      post conversation_lorebooks_url(@own_conversation),
           params: { conversation_lorebook: { lorebook_id: @own_lorebook.id } },
           as: :turbo_stream
    end

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "destroy detaches a lorebook from conversation" do
    attachment = ConversationLorebook.create!(conversation: @own_conversation, lorebook: @own_lorebook)

    assert_difference "ConversationLorebook.count", -1 do
      delete conversation_lorebook_url(@own_conversation, attachment)
    end

    assert_redirected_to conversation_lorebooks_url(@own_conversation)
    assert_not ConversationLorebook.exists?(attachment.id)
  end

  test "destroy with turbo_stream replaces frame" do
    attachment = ConversationLorebook.create!(conversation: @own_conversation, lorebook: @own_lorebook)

    assert_difference "ConversationLorebook.count", -1 do
      delete conversation_lorebook_url(@own_conversation, attachment), as: :turbo_stream
    end

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "toggle enables/disables lorebook attachment" do
    attachment = ConversationLorebook.create!(conversation: @own_conversation, lorebook: @own_lorebook, enabled: true)

    patch toggle_conversation_lorebook_url(@own_conversation, attachment)

    assert_redirected_to conversation_lorebooks_url(@own_conversation)
    attachment.reload
    assert_not attachment.enabled

    # Toggle back
    patch toggle_conversation_lorebook_url(@own_conversation, attachment)
    attachment.reload
    assert attachment.enabled
  end

  test "toggle with turbo_stream replaces the row" do
    attachment = ConversationLorebook.create!(conversation: @own_conversation, lorebook: @own_lorebook, enabled: true)

    patch toggle_conversation_lorebook_url(@own_conversation, attachment), as: :turbo_stream

    assert_response :success
    assert_match "turbo-stream", response.body
    attachment.reload
    assert_not attachment.enabled
  end

  test "reorder updates priorities" do
    lorebook2 = Lorebook.create!(name: "Second Lorebook")
    lorebook3 = Lorebook.create!(name: "Third Lorebook")

    link1 = ConversationLorebook.create!(conversation: @own_conversation, lorebook: @own_lorebook)
    link2 = ConversationLorebook.create!(conversation: @own_conversation, lorebook: lorebook2)
    link3 = ConversationLorebook.create!(conversation: @own_conversation, lorebook: lorebook3)

    # Original order: link1=0, link2=1, link3=2
    # New order: link3, link1, link2
    patch reorder_conversation_lorebooks_url(@own_conversation), params: {
      positions: [link3.id, link1.id, link2.id],
    }

    assert_response :success

    link1.reload
    link2.reload
    link3.reload

    assert_equal 1, link1.priority
    assert_equal 2, link2.priority
    assert_equal 0, link3.priority
  ensure
    lorebook2&.destroy
    lorebook3&.destroy
  end

  test "reorder with invalid params returns bad request" do
    patch reorder_conversation_lorebooks_url(@own_conversation), params: { positions: "invalid" }

    assert_response :bad_request
  end
end
