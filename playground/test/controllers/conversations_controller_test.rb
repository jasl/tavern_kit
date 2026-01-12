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
    # Conversation page uses the conversation title as the page title
    assert_select "title", text: /#{Regexp.escape(conversation.title)}/
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
    assert run.regenerate?
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

  test "retry_stuck_run retries the last failed run (creates a new queued run)" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    failed_run = ConversationRun.create!(
      conversation: conversation,
      speaker_space_membership_id: ai_membership.id,
      kind: "auto_response",
      status: "failed",
      reason: "auto_response",
      error: { "code" => "test_error" }
    )

    assert_difference "ConversationRun.count", 1 do
      post retry_stuck_run_conversation_url(conversation), as: :turbo_stream
    end

    assert_response :success

    new_run = conversation.conversation_runs.order(created_at: :desc).first
    assert new_run.queued?
    assert_equal failed_run.kind, new_run.kind
    assert_equal "retry_failed", new_run.reason
    assert_equal ai_membership.id, new_run.speaker_space_membership_id
  end

  test "retry_stuck_run can retry a failed regenerate run (re-enqueues regenerate)" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    target_message = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")
    target_message.ensure_initial_swipe!

    ConversationRun.create!(
      conversation: conversation,
      speaker_space_membership_id: ai_membership.id,
      kind: "regenerate",
      status: "failed",
      reason: "regenerate",
      error: { "code" => "test_error" },
      debug: {
        "trigger" => "regenerate",
        "target_message_id" => target_message.id,
        "expected_last_message_id" => target_message.id,
      }
    )

    assert_difference "ConversationRun.count", 1 do
      post retry_stuck_run_conversation_url(conversation), as: :turbo_stream
    end

    assert_response :success

    new_run = conversation.conversation_runs.order(created_at: :desc).first
    assert new_run.regenerate?
    assert new_run.queued?
    assert_equal ai_membership.id, new_run.speaker_space_membership_id
    assert_equal target_message.id, new_run.debug["target_message_id"]
    assert_equal target_message.id, new_run.debug["expected_last_message_id"]
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

  test "regenerate in group last_turn mode deletes AI turn and starts a new activated round (natural)" do
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

    # Set talkativeness to 0 for deterministic speaker selection (round-robin)
    space.space_memberships.ai_characters.update_all(talkativeness_factor: 0)

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai1 = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    ai2 = space.space_memberships.find_by!(character: characters(:ready_v3), kind: "character")

    user_msg = conversation.messages.create!(space_membership: user_membership, role: "user", content: "v2 v3")
    conversation.messages.create!(space_membership: ai1, role: "assistant", content: "Hello from 1")
    tail = conversation.messages.create!(space_membership: ai2, role: "assistant", content: "Hello from 2")

    # Creating messages directly triggers TurnScheduler callbacks, which can create a queued run
    # for the initial user message. In the real flow that run would have executed already, so
    # clear it to keep this controller test focused on last_turn regeneration behavior.
    ConversationRun.where(conversation: conversation).delete_all
    conversation.update!(
      scheduling_state: "idle",
      current_round_id: nil,
      current_speaker_id: nil,
      round_position: 0,
      round_spoken_ids: [],
      round_queue_ids: []
    )

    assert_difference "ConversationRun.count", 1 do
      post regenerate_conversation_url(conversation), params: { message_id: tail.id }, as: :turbo_stream
    end

    assert_response :no_content

    # Deletes all messages after the last user message (the AI turn).
    assert_equal [user_msg.id], conversation.reload.messages.order(:seq, :id).pluck(:id)

    conversation.reload
    assert_equal [ai1.id, ai2.id], conversation.round_queue_ids
    assert_equal ai1.id, conversation.current_speaker_id

    run = ConversationRun.order(:created_at, :id).last
    assert run.auto_response?
    assert_equal "queued", run.status
    assert_equal "auto_response", run.reason
    assert_equal "auto_response", run.debug["trigger"]
    assert_equal conversation.current_round_id, run.debug["round_id"]
    assert_equal ai1.id, run.speaker_space_membership_id
  end

  test "regenerate in group last_turn mode starts a multi-speaker round for list order" do
    space =
      Spaces::Playground.create!(
        name: "Group Last Turn Space (list)",
        owner: users(:admin),
        reply_order: "list",
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

    ConversationRun.where(conversation: conversation).delete_all
    conversation.update!(
      scheduling_state: "idle",
      current_round_id: nil,
      current_speaker_id: nil,
      round_position: 0,
      round_spoken_ids: [],
      round_queue_ids: []
    )

    assert_difference "ConversationRun.count", 1 do
      post regenerate_conversation_url(conversation), params: { message_id: tail.id }, as: :turbo_stream
    end

    assert_response :no_content
    assert_equal [user_msg.id], conversation.reload.messages.order(:seq, :id).pluck(:id)

    conversation.reload
    assert_equal [ai1.id, ai2.id], conversation.round_queue_ids

    run = ConversationRun.order(:created_at, :id).last
    assert_equal ai1.id, run.speaker_space_membership_id
  end

  test "regenerate in group last_turn mode starts a single-speaker round for pooled order" do
    space =
      Spaces::Playground.create!(
        name: "Group Last Turn Space (pooled)",
        owner: users(:admin),
        reply_order: "pooled",
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

    ConversationRun.where(conversation: conversation).delete_all
    conversation.update!(
      scheduling_state: "idle",
      current_round_id: nil,
      current_speaker_id: nil,
      round_position: 0,
      round_spoken_ids: [],
      round_queue_ids: []
    )

    assert_difference "ConversationRun.count", 1 do
      post regenerate_conversation_url(conversation), params: { message_id: tail.id }, as: :turbo_stream
    end

    assert_response :no_content
    assert_equal [user_msg.id], conversation.reload.messages.order(:seq, :id).pluck(:id)

    conversation.reload
    assert_equal 1, conversation.round_queue_ids.size
    assert_includes [ai1.id, ai2.id], conversation.round_queue_ids.first
  end

  test "regenerate in group last_turn mode starts a single-speaker round for manual order" do
    space =
      Spaces::Playground.create!(
        name: "Group Last Turn Space (manual)",
        owner: users(:admin),
        reply_order: "manual",
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

    ConversationRun.where(conversation: conversation).delete_all
    conversation.update!(
      scheduling_state: "idle",
      current_round_id: nil,
      current_speaker_id: nil,
      round_position: 0,
      round_spoken_ids: [],
      round_queue_ids: []
    )

    assert_difference "ConversationRun.count", 1 do
      post regenerate_conversation_url(conversation), params: { message_id: tail.id }, as: :turbo_stream
    end

    assert_response :no_content
    assert_equal [user_msg.id], conversation.reload.messages.order(:seq, :id).pluck(:id)

    conversation.reload
    assert_equal 1, conversation.round_queue_ids.size
    assert_includes [ai1.id, ai2.id], conversation.round_queue_ids.first
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
    assert run.force_talk?
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
    assert run.force_talk?
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
    assert run.force_talk?
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

  test "generate in non-manual mode uses TurnScheduler to select speaker" do
    space = Spaces::Playground.create!(name: "Natural Test", owner: users(:admin), reply_order: "natural")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    assert_difference "ConversationRun.count", 1 do
      post generate_conversation_url(conversation), as: :turbo_stream
    end

    run = ConversationRun.order(:created_at, :id).last
    assert run.force_talk?
    assert_includes space.space_memberships.active.ai_characters.pluck(:id), run.speaker_space_membership_id

    assert_response :success
  end

  # === Last Turn Regenerate: Fork Point Auto-Branch Tests ===

  test "regenerate in group last_turn mode auto-branches when fork point exists" do
    space = Spaces::Playground.create!(
      name: "Fork Point Test",
      owner: users(:admin),
      reply_order: "natural",
      group_regenerate_mode: "last_turn"
    )
    space.space_memberships.grant_to(users(:admin), role: "owner")
    # Need 2+ AI characters for group? to return true
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    user_msg = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    ai_msg = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")

    # Create a branch from the AI message (makes it a fork point)
    Conversations::Forker.new(
      parent_conversation: conversation,
      fork_from_message: ai_msg,
      kind: "branch"
    ).call

    original_message_count = conversation.messages.count

    # Regenerate should create a new branch and redirect there
    assert_difference "Conversation.count", 1 do
      post regenerate_conversation_url(conversation), params: { message_id: ai_msg.id }
    end

    # Original messages should still exist
    assert_equal original_message_count, conversation.reload.messages.count

    # Should redirect to the new branch
    new_branch = Conversation.order(:created_at, :id).last
    assert_equal "branch", new_branch.kind
    assert_equal "#{conversation.title} (regenerated)", new_branch.title
    assert_equal user_msg.id, new_branch.forked_from_message_id
    assert_redirected_to conversation_url(new_branch)

    # New branch should have a queued run
    run = ConversationRun.order(:created_at, :id).last
    assert_equal new_branch.id, run.conversation_id
    assert run.auto_response?
  end

  test "regenerate in group last_turn mode without user messages returns warning via html" do
    space = Spaces::Playground.create!(
      name: "No User Msg Test",
      owner: users(:admin),
      reply_order: "natural",
      group_regenerate_mode: "last_turn"
    )
    space.space_memberships.grant_to(users(:admin), role: "owner")
    # Need 2+ AI characters for group? to return true
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    # Only create a greeting (assistant) message, no user messages
    greeting = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello, I am a greeting!")

    assert_no_difference "Conversation.count" do
      assert_no_difference "ConversationRun.count" do
        # Use HTML format to avoid turbo_stream rendering issues in tests
        post regenerate_conversation_url(conversation), params: { message_id: greeting.id }
      end
    end

    assert_redirected_to conversation_url(conversation)
    assert_match(/Nothing to regenerate/, flash[:alert])

    # Greeting should still exist
    assert Message.exists?(greeting.id)
  end

  test "regenerate in group last_turn mode without user messages redirects with alert for html" do
    space = Spaces::Playground.create!(
      name: "No User Msg Test HTML",
      owner: users(:admin),
      reply_order: "natural",
      group_regenerate_mode: "last_turn"
    )
    space.space_memberships.grant_to(users(:admin), role: "owner")
    # Need 2+ AI characters for group? to return true
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    greeting = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello!")

    assert_no_difference "Conversation.count" do
      assert_no_difference "ConversationRun.count" do
        post regenerate_conversation_url(conversation), params: { message_id: greeting.id }
      end
    end

    assert_redirected_to conversation_url(conversation)
    assert_match(/Nothing to regenerate/, flash[:alert])

    # Greeting should still exist
    assert Message.exists?(greeting.id)
  end

  test "regenerate in group last_turn mode preserves greeting when no user messages" do
    space = Spaces::Playground.create!(
      name: "Preserve Greeting Test",
      owner: users(:admin),
      reply_order: "natural",
      group_regenerate_mode: "last_turn"
    )
    space.space_memberships.grant_to(users(:admin), role: "owner")
    # Need 2+ AI characters for group? to return true
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai1 = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    ai2 = space.space_memberships.find_by!(character: characters(:ready_v3), kind: "character")

    # Create multiple greeting messages from different characters
    greeting1 = conversation.messages.create!(space_membership: ai1, role: "assistant", content: "Hello from char 1!")
    greeting2 = conversation.messages.create!(space_membership: ai2, role: "assistant", content: "Hello from char 2!")

    original_count = conversation.messages.count

    # Use HTML format to avoid turbo_stream rendering issues in tests
    post regenerate_conversation_url(conversation), params: { message_id: greeting2.id }

    # All greetings should be preserved
    assert_equal original_count, conversation.reload.messages.count
    assert Message.exists?(greeting1.id)
    assert Message.exists?(greeting2.id)
  end

  test "regenerate in group last_turn mode does not 500 on any error condition" do
    space = Spaces::Playground.create!(
      name: "Error Handling Test",
      owner: users(:admin),
      reply_order: "natural",
      group_regenerate_mode: "last_turn"
    )
    space.space_memberships.grant_to(users(:admin), role: "owner")
    # Need 2+ AI characters for group? to return true
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hi")
    ai_msg = conversation.messages.create!(space_membership: ai_membership, role: "assistant", content: "Hello")

    # Simulate an error by stubbing the service to return an error result
    error_result = Conversations::LastTurnRegenerator::Result.new(
      outcome: :error,
      conversation: conversation,
      error: "Something went wrong",
      deleted_message_ids: nil
    )

    Conversations::LastTurnRegenerator.any_instance.stubs(:call).returns(error_result)

    # Should NOT raise - should handle gracefully (use HTML format to avoid turbo_stream template issues)
    assert_nothing_raised do
      post regenerate_conversation_url(conversation), params: { message_id: ai_msg.id }
    end

    assert_redirected_to conversation_url(conversation)
    assert_equal "Something went wrong", flash[:alert]
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

  # === Stop Generation Tests ===

  test "stop sets cancel_requested_at on running run" do
    space = Spaces::Playground.create!(name: "Stop Test", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    # Create a running run
    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "running",

      reason: "test",
      speaker_space_membership_id: ai_membership.id,
      started_at: Time.current
    )

    assert_nil run.cancel_requested_at

    # Stub broadcasts to avoid channel errors in test
    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_typing)

    post stop_conversation_url(conversation)

    assert_response :no_content
    run.reload
    assert_not_nil run.cancel_requested_at
  end

  test "stop returns 204 even when no running run exists" do
    space = Spaces::Playground.create!(name: "Stop Test No Run", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    # No runs exist
    assert_equal 0, conversation.conversation_runs.count

    post stop_conversation_url(conversation)

    assert_response :no_content
  end

  test "stop returns not_found for non-member" do
    space = Spaces::Playground.create!(name: "Stop Test Non-Member", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")

    conversation = space.conversations.create!(title: "Main", kind: "root")

    # Sign in as a different user who is not a member
    sign_in :member

    post stop_conversation_url(conversation)

    assert_response :not_found
  end

  test "stop is idempotent - second call does not change cancel_requested_at" do
    space = Spaces::Playground.create!(name: "Stop Idempotent Test", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    # Create a running run
    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "running",

      reason: "test",
      speaker_space_membership_id: ai_membership.id,
      started_at: Time.current
    )

    # Stub broadcasts to avoid channel errors in test
    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_typing)

    # First stop call
    post stop_conversation_url(conversation)
    assert_response :no_content

    run.reload
    first_cancel_time = run.cancel_requested_at
    assert_not_nil first_cancel_time

    # Second stop call (should not change the timestamp)
    travel 1.second do
      post stop_conversation_url(conversation)
      assert_response :no_content

      run.reload
      assert_equal first_cancel_time, run.cancel_requested_at
    end
  end

  test "stop broadcasts stream_complete and typing_stop" do
    space = Spaces::Playground.create!(name: "Stop Broadcast Test", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    # Create a running run
    run = ConversationRun.create!(kind: "auto_response", conversation: conversation,
      status: "running",

      reason: "test",
      speaker_space_membership_id: ai_membership.id,
      started_at: Time.current
    )

    # Set expectations for broadcasts
    ConversationChannel.expects(:broadcast_stream_complete).with(conversation, space_membership_id: ai_membership.id).once
    ConversationChannel.expects(:broadcast_typing).with(conversation, membership: ai_membership, active: false).once

    post stop_conversation_url(conversation)

    assert_response :no_content
  end

  test "stop returns forbidden when space is archived" do
    space = Spaces::Playground.create!(name: "Archived Stop Test", owner: users(:admin), status: "archived")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    post stop_conversation_url(conversation)

    assert_response :forbidden
  end
end
