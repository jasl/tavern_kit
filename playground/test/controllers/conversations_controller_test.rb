# frozen_string_literal: true

require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :admin
  end

  test "create creates a root conversation in a playground" do
    playground = spaces(:general)

    assert_difference "Conversation.count", 1 do
      post playground_conversations_url(playground), params: { conversation: { title: "New Conversation" } }
    end

    conversation = Conversation.order(:created_at, :id).last
    assert_equal playground, conversation.space
    assert_equal "root", conversation.kind
    assert_redirected_to conversation_url(conversation)
  end

  test "show renders the conversation page" do
    conversation = conversations(:general_main)

    get conversation_url(conversation)
    assert_response :success
    assert_select "h1", text: conversation.title
  end

  test "branch returns error message when space is not playground" do
    conversation = conversations(:discussion_main)
    msg = messages(:discussion_user_message)

    post branch_conversation_url(conversation), params: { message_id: msg.id }
    assert_redirected_to conversation_url(conversation)
    assert_equal "Branching is only allowed in Playground spaces", flash[:alert]
  end

  test "branch creates a branched conversation and copies prefix for playground spaces" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    m1 = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    m2 = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")

    m2.ensure_initial_swipe!
    m2.add_swipe!(content: "Hello v2", metadata: { "note" => "alt" })

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Later")

    assert_difference "Conversation.count", 1 do
      post branch_conversation_url(conversation), params: { message_id: m2.id }
    end

    branch = Conversation.order(:created_at, :id).last
    assert_equal "branch", branch.kind
    assert_equal conversation, branch.parent_conversation
    assert_equal m2, branch.forked_from_message
    assert_redirected_to conversation_url(branch)

    copied = branch.messages.ordered.to_a
    assert_equal 2, copied.size
    assert_equal [m1.seq, m2.seq], copied.map(&:seq)
    assert_equal [m1.content, m2.content], copied.map(&:content)
    assert_equal [user_membership.id, ai_membership.id], copied.map(&:space_membership_id)

    # Verify origin_message_id is set
    assert_equal m1.id, copied.first.origin_message_id
    assert_equal m2.id, copied.last.origin_message_id

    copied_m2 = copied.last
    assert_equal 2, copied_m2.message_swipes.size
    assert_equal [0, 1], copied_m2.message_swipes.ordered.pluck(:position)
    assert_equal ["Hello", "Hello v2"], copied_m2.message_swipes.ordered.pluck(:content)

    assert_equal 1, copied_m2.active_message_swipe.position
    assert_equal "Hello v2", copied_m2.active_message_swipe.content
    refute_equal m2.active_message_swipe_id, copied_m2.active_message_swipe_id
  end

  test "regenerate on last assistant message does not branch" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    last_assistant = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")

    assert_no_difference "Conversation.count" do
      post regenerate_conversation_url(conversation), params: { message_id: last_assistant.id }
    end

    # Should stay on same conversation (regenerate happens in place)
    assert_response :redirect
    assert_redirected_to conversation_url(conversation, anchor: "message_#{last_assistant.id}")
  end

  test "regenerate on non-last assistant message auto-branches and regenerates in branch" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    first_assistant = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Thanks")
    conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "You're welcome")

    # Regenerating the FIRST assistant message should auto-branch
    assert_difference "Conversation.count", 1 do
      post regenerate_conversation_url(conversation), params: { message_id: first_assistant.id }
    end

    branch = Conversation.order(:created_at, :id).last
    assert_equal "branch", branch.kind
    assert_equal conversation, branch.parent_conversation
    assert_equal first_assistant, branch.forked_from_message

    # Branch should contain only 2 messages (up to first_assistant)
    assert_equal 2, branch.messages.count

    # Original conversation should be unchanged
    assert_equal 4, conversation.messages.count

    # Should redirect to branch conversation
    assert_redirected_to conversation_url(branch)
  end
end
