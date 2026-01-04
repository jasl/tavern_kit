# frozen_string_literal: true

require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    @mock_provider = llm_providers(:mock_local)
  end

  # ============================================================================
  # Helper Methods
  # ============================================================================

  # Sign in via the login form
  def sign_in_as(user)
    visit new_session_url
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign in"
    assert_text "Playgrounds" # Wait for redirect to complete
  end

  # Create a playground with a single character using the mock provider
  def create_test_playground(name: "Test Playground")
    character = characters(:ready_v2)

    visit new_playground_url
    fill_in "Name", with: name
    check character.name # Select the character

    # Select the mock provider if available
    if page.has_select?("LLM Provider")
      select @mock_provider.name, from: "LLM Provider"
    end

    click_button "Create"
    assert_current_path %r{/playgrounds/\d+}
  end

  # Wait for a condition with timeout
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
  # 1. Authentication & First Run
  # ============================================================================

  test "unauthenticated user is redirected to login" do
    conversation = conversations(:general_main)
    visit conversation_url(conversation)

    # Should redirect to login or root
    assert_no_current_path conversation_url(conversation)
  end

  test "user can sign in and access playgrounds" do
    visit new_session_url
    fill_in "Email", with: @admin.email
    fill_in "Password", with: "password123"
    click_button "Sign in"

    assert_text "Playgrounds"
  end

  # ============================================================================
  # 2. Playground Management
  # ============================================================================

  test "can create a new playground with a character" do
    sign_in_as(@admin)

    visit new_playground_url
    fill_in "Name", with: "My Test Playground"
    check characters(:ready_v2).name

    click_button "Create"

    # Should redirect to the playground (conversation)
    assert_current_path %r{/playgrounds/\d+}
    assert_text "My Test Playground"
  end

  # ============================================================================
  # 3. Basic Chat Flow (Single Character)
  # ============================================================================

  test "can send a message and receive AI response" do
    sign_in_as(@admin)

    # Create a fresh playground for this test
    space = Spaces::Playground.create!(
      name: "Chat Test Space",
      owner: @admin,
      reply_order: "natural",
      during_generation_user_input_policy: "queue",
      user_turn_debounce_ms: 0
    )
    space.space_memberships.grant_to(@admin, role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    # Set up the mock provider for this space
    space.update!(llm_provider: @mock_provider)

    conversation = space.conversations.create!(title: "Test Chat", kind: "root")

    visit conversation_url(conversation)

    # Send a message
    fill_in "message[content]", with: "Hello, AI!"
    find("#message_form button[type='submit']", wait: 5).click

    # Wait for user message to appear
    assert_selector "[data-message-role='user']", text: "Hello, AI!", wait: 10

    # Wait for AI response (the mock will respond with something containing "Hello")
    assert_selector "[data-message-role='assistant']", wait: 30

    # Verify message persists after refresh
    refresh
    assert_selector "[data-message-role='user']", text: "Hello, AI!"
    assert_selector "[data-message-role='assistant']"
  end

  test "messages persist after page refresh" do
    sign_in_as(@admin)

    # Set up a conversation with existing messages
    conversation = conversations(:general_main)
    space = conversation.space
    user_membership = space.space_memberships.find_by!(user: @admin)
    ai_membership = space.space_memberships.where(kind: "character").first

    # Create test messages
    conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Test persistence message"
    )
    conversation.messages.create!(
      space_membership: ai_membership,
      role: "assistant",
      content: "AI persistence response"
    )

    visit conversation_url(conversation)

    assert_text "Test persistence message"
    assert_text "AI persistence response"

    # Refresh and verify
    refresh

    assert_text "Test persistence message"
    assert_text "AI persistence response"
  end

  # ============================================================================
  # 4. Regenerate & Swipe
  # ============================================================================

  test "regenerate creates a new swipe without adding new message" do
    sign_in_as(@admin)

    # Set up conversation with messages
    space = Spaces::Playground.create!(
      name: "Regenerate Test Space",
      owner: @admin,
      reply_order: "natural"
    )
    space.space_memberships.grant_to(@admin, role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.update!(llm_provider: @mock_provider)

    conversation = space.conversations.create!(title: "Regen Test", kind: "root")
    user_membership = space.space_memberships.find_by!(user: @admin)
    ai_membership = space.space_memberships.where(kind: "character").first

    conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Hello"
    )
    assistant_msg = conversation.messages.create!(
      space_membership: ai_membership,
      role: "assistant",
      content: "Original response"
    )
    assistant_msg.ensure_initial_swipe!

    initial_message_count = conversation.messages.count

    visit conversation_url(conversation)

    # Click regenerate on the assistant message (using the refresh icon button)
    within "#message_#{assistant_msg.id}" do
      find("button[title='Regenerate']", wait: 5).click
    end

    # Wait for regeneration to complete
    sleep 3

    # Verify message count hasn't changed (no new message added)
    assert_equal initial_message_count, conversation.reload.messages.count

    # Verify swipe count increased
    assert_equal 2, assistant_msg.reload.message_swipes_count
  end

  test "can navigate between swipes with arrows" do
    sign_in_as(@admin)

    # Set up conversation with a message that has multiple swipes
    conversation = conversations(:general_main)
    space = conversation.space
    ai_membership = space.space_memberships.where(kind: "character").first
    user_membership = space.space_memberships.find_by!(user: @admin)

    # Clear existing messages and create fresh ones
    conversation.messages.destroy_all

    conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Test swipe navigation"
    )

    assistant_msg = conversation.messages.create!(
      space_membership: ai_membership,
      role: "assistant",
      content: "First version"
    )
    assistant_msg.ensure_initial_swipe!
    assistant_msg.add_swipe!(content: "Second version")
    assistant_msg.add_swipe!(content: "Third version")

    # Set active swipe to position 2 (Third version)
    assistant_msg.update!(active_message_swipe: assistant_msg.message_swipes.find_by(position: 2))

    visit conversation_url(conversation)

    # Verify current swipe is shown
    assert_text "Third version"

    # Click left arrow to go to previous swipe (uses button with title "Previous version")
    within "#message_#{assistant_msg.id}" do
      find("button[title='Previous version']", wait: 5).click
    end

    sleep 1
    assert_text "Second version"

    # Click left arrow again
    within "#message_#{assistant_msg.id}" do
      find("button[title='Previous version']", wait: 5).click
    end

    sleep 1
    assert_text "First version"
  end

  # ============================================================================
  # 5. Branching
  # ============================================================================

  test "can create a branch from a message" do
    sign_in_as(@admin)

    # Set up conversation with messages
    space = Spaces::Playground.create!(
      name: "Branch Test Space",
      owner: @admin,
      reply_order: "natural"
    )
    space.space_memberships.grant_to(@admin, role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Branch Test", kind: "root")
    user_membership = space.space_memberships.find_by!(user: @admin)
    ai_membership = space.space_memberships.where(kind: "character").first

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "First message")
    msg2 = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "First response")
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Second message")
    conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Second response")

    initial_conversation_count = Conversation.count

    visit conversation_url(conversation)

    # Find and click branch button on msg2 (using title "Branch from here")
    within "#message_#{msg2.id}" do
      find("button[title='Branch from here']", wait: 5).click
    end

    # Should create a new conversation and redirect
    sleep 2
    assert_equal initial_conversation_count + 1, Conversation.count

    # The new branch should only have 2 messages (up to msg2)
    branch = Conversation.order(:created_at).last
    assert_equal "branch", branch.kind
    assert_equal 2, branch.messages.count
    assert_current_path conversation_url(branch)
  end

  # ============================================================================
  # 6. Archive/Read-only State
  # ============================================================================

  test "archived playground shows read-only indicator" do
    sign_in_as(@admin)

    space = spaces(:archived_space)
    # Ensure the user has membership
    space.space_memberships.find_or_create_by!(user: @admin) do |m|
      m.kind = "human"
      m.role = "owner"
    end

    conversation = space.conversations.first_or_create!(title: "Archived Chat", kind: "root")

    visit conversation_url(conversation)

    # Should show archived alert or disabled input
    within "#message_form" do
      # Either we see the archived alert or the textarea is disabled
      has_archived_alert = page.has_text?("archived and read-only")
      has_disabled_input = page.has_selector?("textarea[disabled]")
      assert has_archived_alert || has_disabled_input, "Expected archived indicator or disabled input"
    end
  end
end
