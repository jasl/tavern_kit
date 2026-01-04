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

  test "regenerate on tail assistant message does not branch" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    tail_assistant = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")

    assert_no_difference "Conversation.count" do
      post regenerate_conversation_url(conversation), params: { message_id: tail_assistant.id }
    end

    # Should stay on same conversation (regenerate happens in place)
    assert_response :redirect
    assert_redirected_to conversation_url(conversation, anchor: "message_#{tail_assistant.id}")
  end

  test "regenerate on tail assistant via turbo_stream returns 204 and creates run" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    tail_assistant = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")
    tail_assistant.ensure_initial_swipe!

    initial_swipe_count = tail_assistant.message_swipes.count

    assert_no_difference "Conversation.count" do
      assert_difference "ConversationRun.count", 1 do
        post regenerate_conversation_url(conversation), params: { message_id: tail_assistant.id }, as: :turbo_stream
      end
    end

    assert_response :no_content

    # Verify a regenerate run was created
    run = ConversationRun.order(:created_at, :id).last
    assert_equal "regenerate", run.kind
    assert_equal "queued", run.status
    assert_equal ai_membership.id, run.speaker_space_membership_id

    # Note: swipe count increases after the run executes, not at planning time
    # The initial swipe count should remain the same at this point
    assert_equal initial_swipe_count, tail_assistant.reload.message_swipes.count
  end

  test "regenerate without message_id when tail is user message returns error" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")
    # Tail is now a user message
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Thanks")

    assert_no_difference "Conversation.count" do
      assert_no_difference "ConversationRun.count" do
        post regenerate_conversation_url(conversation)
      end
    end

    assert_redirected_to conversation_url(conversation)
    assert_equal "Last message is not assistant.", flash[:alert]
  end

  test "regenerate without message_id when tail is user message returns 422 for turbo_stream" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")
    # Tail is now a user message
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Thanks")

    assert_no_difference "ConversationRun.count" do
      post regenerate_conversation_url(conversation), as: :turbo_stream
    end

    assert_response :unprocessable_entity
  end

  test "regenerate with message_id for non-assistant message returns 422" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    user_message = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")

    # Explicitly try to regenerate a user message
    assert_no_difference "Conversation.count" do
      assert_no_difference "ConversationRun.count" do
        post regenerate_conversation_url(conversation), params: { message_id: user_message.id }, as: :turbo_stream
      end
    end

    assert_response :unprocessable_entity
  end

  test "regenerate with message_id for non-assistant message redirects with error for html" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    user_message = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")

    # Explicitly try to regenerate a user message
    assert_no_difference "ConversationRun.count" do
      post regenerate_conversation_url(conversation), params: { message_id: user_message.id }
    end

    assert_redirected_to conversation_url(conversation)
    assert_equal "Cannot regenerate non-assistant message.", flash[:alert]
  end

  test "regenerate on non-tail assistant message auto-branches and regenerates in branch" do
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

    # Regenerating a non-tail assistant message should auto-branch
    # (first_assistant is not the tail - tail is "You're welcome")
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

  test "regenerate on non-tail assistant when tail is user message auto-branches" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    assistant_msg = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")
    # Tail is a user message, not an assistant message
    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Thanks")

    # Regenerating the assistant message should auto-branch since it's not the tail
    assert_difference "Conversation.count", 1 do
      post regenerate_conversation_url(conversation), params: { message_id: assistant_msg.id }
    end

    branch = Conversation.order(:created_at, :id).last
    assert_equal "branch", branch.kind
    assert_equal conversation, branch.parent_conversation
    assert_equal assistant_msg, branch.forked_from_message

    # Branch should contain only 2 messages (up to assistant_msg)
    assert_equal 2, branch.messages.count

    # Original conversation should be unchanged
    assert_equal 3, conversation.messages.count

    # Should redirect to branch conversation
    assert_redirected_to conversation_url(branch)
  end

  test "regenerate in group last_turn mode deletes AI turn and enqueues a user_turn run" do
    space =
      Spaces::Playground.create!(
        name: "Group Last Turn Space",
        owner: users(:admin),
        reply_order: "natural",
        group_regenerate_mode: "last_turn"
      )
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai1 = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    ai2 = space.space_memberships.find_by!(character: characters(:ready_v3), kind: "character")

    user_msg = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    conversation.messages.create!(space_membership: ai1, role: "assistant", content: "Hello from 1")
    tail = conversation.messages.create!(space_membership: ai2, role: "assistant", content: "Hello from 2")

    assert_difference "ConversationRun.count", 1 do
      post regenerate_conversation_url(conversation), params: { message_id: tail.id }, as: :turbo_stream
    end

    assert_response :no_content

    # Deletes all messages after the last user message (the AI turn).
    assert_equal [user_msg.id], conversation.reload.messages.order(:seq, :id).pluck(:id)

    run = ConversationRun.order(:created_at, :id).last
    assert_equal "user_turn", run.kind
    assert_equal "queued", run.status
    assert_equal "regenerate_turn", run.reason
    assert_equal "regenerate_turn", run.debug["trigger"]
    assert_equal ai1.id, run.speaker_space_membership_id
  end

  # === Generate Endpoint Tests ===

  test "generate without speaker_id selects random speaker in manual mode" do
    space = Spaces::Playground.create!(name: "Manual Test", owner: users(:admin), reply_order: "manual")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    assert_difference "ConversationRun.count", 1 do
      post generate_conversation_url(conversation), as: :turbo_stream
    end

    run = ConversationRun.order(:created_at, :id).last
    assert_equal "force_talk", run.kind
    assert_equal "queued", run.status

    # Speaker should be the AI character membership
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    assert_equal ai_membership.id, run.speaker_space_membership_id

    assert_response :success
  end

  test "generate with speaker_id uses force_talk for specified speaker" do
    space = Spaces::Playground.create!(name: "Force Talk Test", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    # Pick the second AI character
    target_membership = space.space_memberships.find_by!(character: characters(:ready_v3), kind: "character")

    assert_difference "ConversationRun.count", 1 do
      post generate_conversation_url(conversation), params: { speaker_id: target_membership.id }, as: :turbo_stream
    end

    run = ConversationRun.order(:created_at, :id).last
    assert_equal "force_talk", run.kind
    assert_equal target_membership.id, run.speaker_space_membership_id

    assert_response :success
  end

  test "generate with speaker_id works for muted members" do
    space = Spaces::Playground.create!(name: "Muted Test", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    # Mute the AI character
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    ai_membership.update!(participation: "muted")

    assert_difference "ConversationRun.count", 1 do
      post generate_conversation_url(conversation), params: { speaker_id: ai_membership.id }, as: :turbo_stream
    end

    run = ConversationRun.order(:created_at, :id).last
    assert_equal "force_talk", run.kind
    assert_equal ai_membership.id, run.speaker_space_membership_id

    assert_response :success
  end

  test "generate returns error when no AI character available" do
    # Create a space with only human member
    space = Spaces::Playground.create!(name: "No AI Test", owner: users(:admin), reply_order: "manual")
    space.space_memberships.grant_to(users(:admin), role: "owner")

    conversation = space.conversations.create!(title: "Main", kind: "root")

    assert_no_difference "ConversationRun.count" do
      post generate_conversation_url(conversation), as: :turbo_stream
    end

    assert_response :unprocessable_entity
  end

  test "generate in non-manual mode uses SpeakerSelector" do
    space = Spaces::Playground.create!(name: "Natural Test", owner: users(:admin), reply_order: "natural")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    assert_difference "ConversationRun.count", 1 do
      post generate_conversation_url(conversation), as: :turbo_stream
    end

    run = ConversationRun.order(:created_at, :id).last
    assert_equal "force_talk", run.kind
    # Should select first AI character by position (SpeakerSelector behavior)
    ai_membership = space.space_memberships.active.ai_characters.by_position.first
    assert_equal ai_membership.id, run.speaker_space_membership_id

    assert_response :success
  end

  # === Branch Writable Protection Tests ===

  test "branch returns forbidden when space is archived" do
    space = Spaces::Playground.create!(name: "Archived Space", owner: users(:admin), status: "archived")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    message = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")

    assert_no_difference "Conversation.count" do
      post branch_conversation_url(conversation), params: { message_id: message.id }
    end

    assert_response :forbidden
  end
end
