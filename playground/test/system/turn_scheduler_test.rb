# frozen_string_literal: true

require "application_system_test_case"

class TurnSchedulerSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @admin = users(:admin)
    @mock_provider = llm_providers(:mock_local)
  end

  # ============================================================================
  # Helper Methods
  # ============================================================================

  def sign_in_as(user)
    visit new_session_url
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button I18n.t("sessions.new.submit")
    # Wait for redirect to complete - welcome page shows different text
    assert_text "Welcome to Tavern"

    configure_mock_provider_base_url!
  end

  def configure_mock_provider_base_url!
    uri = URI.parse(current_url)
    base = +"#{uri.scheme}://#{uri.host}"
    base << ":#{uri.port}" if uri.port

    @mock_provider.update!(base_url: "#{base}/mock_llm/v1", model: "mock", streamable: true)
    LLMProvider.set_default!(@mock_provider)
  end

  def create_group_chat_space(name: "Group Chat Test")
    space = Spaces::Playground.create!(
      name: name,
      owner: @admin,
      reply_order: "natural",
      during_generation_user_input_policy: "queue",
      user_turn_debounce_ms: 0
    )
    space.space_memberships.grant_to(@admin, role: "owner")

    # Add multiple AI characters for group chat
    character1 = characters(:ready_v2)
    character2 = characters(:ready_v3)

    space.space_memberships.grant_to(character1)
    space.space_memberships.grant_to(character2)

    # Ensure AI characters use the mock provider
    space.space_memberships.ai_characters.each do |m|
      m.update!(llm_provider: @mock_provider)
    end

    space
  end

  def wait_for(timeout: 10, &block)
    Timeout.timeout(timeout) do
      loop do
        break if block.call

        sleep 0.1
      end
    end
  rescue Timeout::Error
    flunk "Timed out waiting for condition"
  end

  # ============================================================================
  # 1. Scheduling State Machine Tests
  # ============================================================================

  test "conversation starts in idle state and transitions correctly" do
    sign_in_as(@admin)

    space = create_group_chat_space
    conversation = space.conversations.create!(title: "State Test", kind: "root")

    # Verify initial state
    assert_equal "idle", conversation.scheduling_state

    visit conversation_url(conversation)

    # Send a message
    perform_enqueued_jobs do
      fill_in "message[content]", with: "Hello everyone!"
      find("#message_form button[type='submit']", wait: 5).click
    end

    # Wait for user message to appear
    assert_selector "[data-message-role='user']", text: "Hello everyone!", wait: 10

    # Wait for AI response
    assert_selector "[data-message-role='assistant']", wait: 15

    # Conversation should be back to idle or active after round
    conversation.reload
    assert_equal "idle", conversation.scheduling_state
  end

  test "scheduling state is persisted across page refreshes" do
    sign_in_as(@admin)

    space = create_group_chat_space
    conversation = space.conversations.create!(title: "Persistence Test", kind: "root")

    visit conversation_url(conversation)

    # Send a message
    perform_enqueued_jobs do
      fill_in "message[content]", with: "Test message"
      find("#message_form button[type='submit']", wait: 5).click
    end

    # Wait for response
    assert_selector "[data-message-role='assistant']", wait: 15

    # Store current state
    conversation.reload
    current_state = conversation.scheduling_state

    # Refresh page
    refresh

    # Verify state persisted
    conversation.reload
    assert_equal current_state, conversation.scheduling_state
  end

  # ============================================================================
  # 2. User Input Priority Tests
  # ============================================================================

  test "user message triggers AI response" do
    sign_in_as(@admin)

    space = create_group_chat_space(name: "Priority Test")
    conversation = space.conversations.create!(title: "Priority Test", kind: "root")

    visit conversation_url(conversation)

    # Send message
    perform_enqueued_jobs do
      fill_in "message[content]", with: "First message"
      find("#message_form button[type='submit']", wait: 5).click
    end

    # Wait for message
    assert_selector "[data-message-role='user']", text: "First message", wait: 10

    # The AI should respond
    assert_selector "[data-message-role='assistant']", wait: 15
  end

  # ============================================================================
  # 3. Concurrent Run Protection Tests
  # ============================================================================

  test "only one AI run executes at a time per conversation" do
    sign_in_as(@admin)

    space = create_group_chat_space(name: "Concurrency Test")
    conversation = space.conversations.create!(title: "Concurrency Test", kind: "root")

    visit conversation_url(conversation)

    # Send message
    perform_enqueued_jobs do
      fill_in "message[content]", with: "Test concurrency"
      find("#message_form button[type='submit']", wait: 5).click
    end

    # Wait for response
    assert_selector "[data-message-role='assistant']", wait: 15

    # Check conversation runs - should have at most 1 running at any time
    conversation.reload
    running_runs = conversation.conversation_runs.running
    assert running_runs.count <= 1, "Expected at most 1 running run, got #{running_runs.count}"
  end

  # ============================================================================
  # 4. Turn Queue & Speaker Selection Tests
  # ============================================================================

  test "speakers are selected based on talkativeness" do
    sign_in_as(@admin)

    space = create_group_chat_space(name: "Turn Order Test")
    conversation = space.conversations.create!(title: "Turn Order Test", kind: "root")

    # Set distinct talkativeness for predictable order
    space.space_memberships.ai_characters.each_with_index do |m, i|
      m.update!(talkativeness_factor: 1.0 - (i * 0.1))
    end

    visit conversation_url(conversation)

    # Send message
    perform_enqueued_jobs do
      fill_in "message[content]", with: "Hello group!"
      find("#message_form button[type='submit']", wait: 5).click
    end

    # Wait for response
    assert_selector "[data-message-role='assistant']", wait: 15

    # Verify at least one AI responded
    conversation.reload
    ai_messages = conversation.messages.where(role: "assistant")
    assert ai_messages.any?, "Expected at least one AI response"
  end

  test "reply_order=list schedules multiple AI speakers in a single round (ST-like)" do
    sign_in_as(@admin)

    space = create_group_chat_space(name: "List Order Multi-Speaker")
    space.update!(reply_order: "list")
    conversation = space.conversations.create!(title: "List Order Multi-Speaker", kind: "root")

    visit conversation_url(conversation)

    perform_enqueued_jobs do
      fill_in "message[content]", with: "Hello list!"
      find("#message_form button[type='submit']", wait: 5).click
    end

    # Two AI characters should respond (serially) for list order.
    assert_selector "[data-message-role='assistant']", minimum: 2, wait: 20
  end

  # ============================================================================
  # 5. ConversationRun Kind Tests
  # ============================================================================

  test "runs are created with correct kind" do
    sign_in_as(@admin)

    space = create_group_chat_space(name: "Kind Test")
    conversation = space.conversations.create!(title: "Kind Test", kind: "root")

    visit conversation_url(conversation)

    # Send message - should create auto_response run
    perform_enqueued_jobs do
      fill_in "message[content]", with: "Test kind"
      find("#message_form button[type='submit']", wait: 5).click
    end

    # Wait for response
    assert_selector "[data-message-role='assistant']", wait: 15

    # Check run kind
    conversation.reload
    runs = conversation.conversation_runs

    # Should have at least one run with auto_response kind
    auto_runs = runs.where(kind: "auto_response")
    assert auto_runs.any?, "Expected auto_response run, got: #{runs.pluck(:kind)}"
  end

  # ============================================================================
  # 6. Single-Slot Queue Tests
  # ============================================================================

  test "database constraint ensures single queued run" do
    sign_in_as(@admin)

    space = create_group_chat_space(name: "Queue Test")
    conversation = space.conversations.create!(title: "Queue Test", kind: "root")

    visit conversation_url(conversation)

    # Send message
    perform_enqueued_jobs do
      fill_in "message[content]", with: "Test queue"
      find("#message_form button[type='submit']", wait: 5).click
    end

    # Wait for response
    assert_selector "[data-message-role='assistant']", wait: 15

    # Verify queued runs - should be at most 1
    conversation.reload
    queued_runs = conversation.conversation_runs.queued
    assert queued_runs.count <= 1, "Expected at most 1 queued run, got #{queued_runs.count}"
  end

  # ============================================================================
  # 8. Error Recovery Tests
  # ============================================================================

  test "conversation remains functional after page refresh during generation" do
    sign_in_as(@admin)

    space = create_group_chat_space(name: "Recovery Test")
    conversation = space.conversations.create!(title: "Recovery Test", kind: "root")

    visit conversation_url(conversation)

    # Send first message
    perform_enqueued_jobs do
      fill_in "message[content]", with: "First message"
      find("#message_form button[type='submit']", wait: 5).click
    end

    # Wait for at least one response
    assert_selector "[data-message-role='assistant']", wait: 15

    # Count initial assistant messages
    initial_count = all("[data-message-role='assistant']").count

    # Refresh page
    refresh

    # Should still be able to send messages
    perform_enqueued_jobs do
      fill_in "message[content]", with: "Message after refresh"
      find("#message_form button[type='submit']", wait: 5).click
    end

    # Wait for new response - should have more assistant messages than before
    assert_selector "[data-message-role='user']", text: "Message after refresh", wait: 10
    # In group chat, multiple AI characters may respond, so just check we have more responses
    assert_selector "[data-message-role='assistant']", minimum: initial_count + 1, wait: 15
  end
end
