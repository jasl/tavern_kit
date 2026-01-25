# frozen_string_literal: true

require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :admin
  end

  test "index shows translated last message preview when translate both is enabled" do
    space = spaces(:general)
    space.update!(prompt_settings: { "i18n" => { "mode" => "translate_both", "target_lang" => "zh-CN" } })

    msg = messages(:ai_response)
    msg.update!(
      metadata: msg.metadata.merge(
        "i18n" => {
          "translations" => {
            "zh-CN" => { "text" => "你好！" },
          },
        }
      )
    )

    get conversations_url
    assert_response :success
    assert_includes response.body, "你好！"
  end

  test "clear_translations clears translations/pending/errors for messages and swipes while preserving user canonical" do
    conversation = conversations(:general_main)
    space = conversation.space
    space.update!(prompt_settings: { "i18n" => { "mode" => "translate_both", "target_lang" => "zh-CN" } })

    user_message = messages(:user_greeting)
    user_message.update!(metadata: user_message.metadata.merge("i18n" => { "canonical" => { "text" => "Hello (canonical)" } }))

    assistant_message = messages(:ai_response)
    assistant_message.ensure_initial_swipe!
    swipe = assistant_message.active_message_swipe
    assert swipe

    message_run =
      TranslationRun.create!(
        conversation: conversation,
        message: assistant_message,
        kind: "message_translation",
        status: "queued",
        source_lang: "en",
        internal_lang: "en",
        target_lang: "zh-CN",
      )

    swipe_run =
      TranslationRun.create!(
        conversation: conversation,
        message: assistant_message,
        message_swipe: swipe,
        kind: "message_translation",
        status: "queued",
        source_lang: "en",
        internal_lang: "en",
        target_lang: "zh-CN",
      )

    assistant_message.update!(
      metadata: assistant_message.metadata.merge(
        "i18n" => {
          "translations" => { "zh-CN" => { "text" => "你好！" } },
          "translation_pending" => { "zh-CN" => true },
          "last_error" => { "code" => "translation_failed", "message" => "boom", "target_lang" => "zh-CN" },
        }
      )
    )

    swipe.update!(
      metadata: {
        "i18n" => {
          "translations" => { "zh-CN" => { "text" => "旧译文" } },
          "translation_pending" => { "zh-CN" => true },
          "last_error" => { "code" => "translation_failed", "message" => "swipe boom", "target_lang" => "zh-CN" },
        },
      }
    )

    post clear_translations_conversation_url(conversation), as: :turbo_stream
    assert_response :ok

    assistant_message.reload
    swipe.reload
    user_message.reload

    assert_nil assistant_message.metadata.dig("i18n", "translations", "zh-CN")
    assert_nil assistant_message.metadata.dig("i18n", "translation_pending", "zh-CN")
    assert_nil assistant_message.metadata.dig("i18n", "last_error")

    assert_nil swipe.metadata.dig("i18n", "translations", "zh-CN")
    assert_nil swipe.metadata.dig("i18n", "translation_pending", "zh-CN")
    assert_nil swipe.metadata.dig("i18n", "last_error")

    assert_equal "Hello (canonical)", user_message.metadata.dig("i18n", "canonical", "text")

    assert_equal "canceled", message_run.reload.status
    assert_equal "canceled", swipe_run.reload.status
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

  test "toggle_auto_without_human enables auto without human and disables auto" do
    space = Spaces::Playground.create!(name: "Auto without human disables Auto", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    persona =
      Character.create!(
        name: "Auto Mode Persona",
        personality: "Test",
        data: { "name" => "Auto Mode Persona" },
        spec_version: 2,
        file_sha256: "auto_persona_#{SecureRandom.hex(8)}",
        status: "ready",
        visibility: "private"
      )

    human = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    human.update!(character: persona, auto: "auto", auto_remaining_steps: 4)
    assert human.auto_enabled?

    Messages::Broadcasts.stubs(:broadcast_auto_disabled)
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    post toggle_auto_without_human_conversation_url(conversation), params: { rounds: 2 }
    assert_redirected_to conversation_url(conversation)

    assert conversation.reload.auto_without_human_enabled?
    assert_equal 2, conversation.auto_without_human_remaining_rounds

    human.reload
    assert human.auto_none?
    assert_nil human.auto_remaining_steps
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

    # Note: swipe count increases immediately (placeholder swipe) so the UI can show "new swipe generating"
    tail_assistant.reload
    assert_equal initial_swipe_count + 1, tail_assistant.message_swipes.count
    assert_equal "generating", tail_assistant.generation_status
    assert_equal run.id, tail_assistant.conversation_run_id

    placeholder_id = run.debug["regenerate_placeholder_swipe_id"]
    assert placeholder_id.present?
    assert_equal placeholder_id, tail_assistant.active_message_swipe_id
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

  test "retry_stuck_run retries current speaker when scheduler is failed (same round)" do
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "failed", current_position: 0)
    round.participants.create!(space_membership: ai_membership, position: 0, status: "pending")

    ConversationRun.create!(
      conversation: conversation,
      conversation_round_id: round.id,
      speaker_space_membership_id: ai_membership.id,
      kind: "auto_response",
      status: "failed",
      reason: "auto_response",
      error: { "code" => "test_error" },
      debug: {
        "trigger" => "auto_response",
        "scheduled_by" => "turn_scheduler",
      }
    )

    assert_difference "ConversationRun.count", 1 do
      post retry_stuck_run_conversation_url(conversation), as: :turbo_stream
    end

    assert_response :success

    new_run = conversation.conversation_runs.order(created_at: :desc).first
    assert new_run.queued?
    assert_equal "auto_response", new_run.kind
    assert_equal "auto_response", new_run.reason
    assert_equal "turn_scheduler", new_run.debug["scheduled_by"]
    assert_equal round.id, new_run.conversation_round_id

    assert_equal "ai_generating", TurnScheduler.state(conversation.reload).scheduling_state
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

  test "cancel_stuck_run cancels active run and clears scheduling state" do
    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_typing)
    Messages::Broadcasts.stubs(:broadcast_auto_disabled)
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    conversation.start_auto_without_human!(rounds: 2)

    persona =
      Character.create!(
        name: "Cancel Stuck Persona",
        personality: "Test",
        data: { "name" => "Cancel Stuck Persona" },
        spec_version: 2,
        file_sha256: "cancel_stuck_persona_#{SecureRandom.hex(8)}",
        status: "ready",
        visibility: "private"
      )

    human = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    human.update!(character: persona, auto: "auto", auto_remaining_steps: 4)
    assert human.auto_enabled?

    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "ai_generating", current_position: 0)
    round.participants.create!(space_membership: ai_membership, position: 0, status: "pending")

    run = ConversationRun.create!(
      conversation: conversation,
      conversation_round_id: round.id,
      speaker_space_membership_id: ai_membership.id,
      kind: "auto_response",
      status: "running",
      reason: "test",
      started_at: Time.current
    )

    post cancel_stuck_run_conversation_url(conversation), as: :turbo_stream

    assert_turbo_stream(action: "show_toast")

    assert_equal "canceled", run.reload.status

    state = TurnScheduler.state(conversation.reload)
    assert_equal "idle", state.scheduling_state
    assert_nil state.current_round_id
    assert_nil state.current_speaker_id
    assert_equal [], state.round_queue_ids

    assert_not conversation.auto_without_human_enabled?

    human.reload
    assert human.auto_none?
    assert_nil human.auto_remaining_steps
  end

  test "cancel_stuck_run returns info toast when no active run exists" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    post cancel_stuck_run_conversation_url(conversation), as: :turbo_stream

    assert_turbo_stream(action: "show_toast")
    assert_match(/no active run/i, response.body)
  end

  test "recover_idle starts a new round when health is idle_unexpected" do
    TurnScheduler::Broadcasts.stubs(:queue_updated)
    ConversationRunJob.stubs(:perform_later)

    # Prevent message after_create_commit from starting the scheduler automatically.
    TurnScheduler.stubs(:advance_turn!).returns(false)

    space = Spaces::Playground.create!(name: "Idle Recovery Space", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    user_membership = space.space_memberships.find_by!(user: users(:admin), kind: "human")

    msg = conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hello")
    msg.update_column(:created_at, 20.seconds.ago)

    assert_equal "idle_unexpected", Conversations::HealthChecker.check(conversation)[:status]

    assert_difference "ConversationRound.count", 1 do
      assert_difference "ConversationRun.count", 1 do
        post recover_idle_conversation_url(conversation)
      end
    end
    assert_response :no_content

    conversation.reload
    assert_equal 1, conversation.conversation_rounds.where(status: "active").count
    assert_equal 1, conversation.conversation_runs.queued.count
  end

  test "stop_round stops the active round and disables automated modes" do
    Messages::Broadcasts.stubs(:broadcast_auto_disabled)
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    space = Spaces::Playground.create!(name: "Stop Round Space", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    conversation.start_auto_without_human!(rounds: 3)

    persona =
      Character.create!(
        name: "Stop Round Persona",
        personality: "Test",
        data: { "name" => "Stop Round Persona" },
        spec_version: 2,
        file_sha256: "stop_round_persona_#{SecureRandom.hex(8)}",
        status: "ready",
        visibility: "private"
      )

    human = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    human.update!(character: persona, auto: "auto", auto_remaining_steps: 4)
    assert human.auto_enabled?

    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "failed", current_position: 0)
    round.participants.create!(space_membership: ai_membership, position: 0, status: "pending")

    post stop_round_conversation_url(conversation), as: :turbo_stream

    assert_response :success
    assert_turbo_stream(action: "replace", target: ActionView::RecordIdentifier.dom_id(conversation, :group_queue))
    assert_turbo_stream(action: "show_toast")

    assert_not conversation.reload.auto_without_human_enabled?

    human.reload
    assert human.auto_none?
    assert_nil human.auto_remaining_steps

    assert_equal "canceled", round.reload.status
    assert_nil round.scheduling_state
    assert_equal "stop_round", round.ended_reason

    state = TurnScheduler.state(conversation.reload)
    assert_equal "idle", state.scheduling_state
  end

  test "pause_round pauses the active round and cancels the queued scheduler run" do
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    space = Spaces::Playground.create!(name: "Pause Round Space", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "ai_generating", current_position: 0)
    round.participants.create!(space_membership: ai_membership, position: 0, status: "pending")

    run =
      ConversationRun.create!(
        conversation: conversation,
        conversation_round_id: round.id,
        speaker_space_membership_id: ai_membership.id,
        kind: "auto_response",
        status: "queued",
        reason: "auto_response",
        run_after: Time.current,
        debug: { "scheduled_by" => "turn_scheduler", "trigger" => "auto_response" }
      )

    post pause_round_conversation_url(conversation), as: :turbo_stream

    assert_response :success
    assert_turbo_stream(action: "replace", target: ActionView::RecordIdentifier.dom_id(conversation, :group_queue))
    assert_turbo_stream(action: "show_toast")
    assert_equal "paused", round.reload.scheduling_state
    assert_equal "canceled", run.reload.status
  end

  test "resume_round resumes a paused round and schedules the current speaker immediately" do
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    space = Spaces::Playground.create!(name: "Resume Round Space", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "paused", current_position: 0)
    round.participants.create!(space_membership: ai_membership, position: 0, status: "pending")

    travel_to Time.current.change(usec: 0) do
      post resume_round_conversation_url(conversation), as: :turbo_stream

      assert_response :success
      assert_turbo_stream(action: "replace", target: ActionView::RecordIdentifier.dom_id(conversation, :group_queue))
      assert_turbo_stream(action: "show_toast")

      round.reload
      assert_equal "ai_generating", round.scheduling_state

      queued = conversation.conversation_runs.queued.first
      assert queued
      assert_equal ai_membership.id, queued.speaker_space_membership_id
      assert_in_delta Time.current, queued.run_after, 0.1
    end
  end

  test "pause_round returns conflict when there is no active round" do
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    space = Spaces::Playground.create!(name: "Pause Round Conflict Space", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")

    conversation = space.conversations.create!(title: "Main", kind: "root")

    post pause_round_conversation_url(conversation), as: :turbo_stream

    assert_response :conflict
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, 'action="show_toast"'
  end

  test "resume_round returns conflict when another run is active" do
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    space = Spaces::Playground.create!(name: "Resume Round Conflict Space", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")

    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "paused", current_position: 0)
    round.participants.create!(space_membership: ai_membership, position: 0, status: "pending")

    ConversationRun.create!(
      conversation: conversation,
      kind: "force_talk",
      status: "queued",
      reason: "force_talk",
      speaker_space_membership_id: ai_membership.id,
      run_after: Time.current,
      debug: { "trigger" => "force_talk" }
    )

    post resume_round_conversation_url(conversation), as: :turbo_stream

    assert_response :conflict
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, 'action="show_toast"'
    assert_equal "paused", round.reload.scheduling_state
  end

  test "skip_turn skips current speaker and disables automated modes" do
    Messages::Broadcasts.stubs(:broadcast_auto_disabled)
    TurnScheduler::Broadcasts.stubs(:queue_updated)

    space = Spaces::Playground.create!(name: "Skip Turn Space", owner: users(:admin), reply_order: "list")
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    conversation.start_auto_without_human!(rounds: 3)

    persona =
      Character.create!(
        name: "Skip Turn Persona",
        personality: "Test",
        data: { "name" => "Skip Turn Persona" },
        spec_version: 2,
        file_sha256: "skip_turn_persona_#{SecureRandom.hex(8)}",
        status: "ready",
        visibility: "private"
      )

    human = space.space_memberships.find_by!(user: users(:admin), kind: "human")
    human.update!(character: persona, auto: "auto", auto_remaining_steps: 4)
    assert human.auto_enabled?

    first_ai = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
    next_ai = space.space_memberships.find_by!(character: characters(:ready_v3), kind: "character")

    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "failed", current_position: 0)
    round.participants.create!(space_membership: first_ai, position: 0, status: "pending")
    round.participants.create!(space_membership: next_ai, position: 1, status: "pending")

    assert_equal 0, conversation.conversation_runs.queued.count

    post skip_turn_conversation_url(conversation), as: :turbo_stream

    assert_response :success
    assert_turbo_stream(action: "replace", target: ActionView::RecordIdentifier.dom_id(conversation, :group_queue))
    assert_turbo_stream(action: "show_toast")

    assert_not conversation.reload.auto_without_human_enabled?

    human.reload
    assert human.auto_none?
    assert_nil human.auto_remaining_steps

    round.reload
    assert_equal 1, round.current_position
    assert_equal "ai_generating", round.scheduling_state
    assert_equal "pending", round.participants.find_by!(space_membership_id: next_ai.id).status
    assert_equal "skipped", round.participants.find_by!(space_membership_id: first_ai.id).status

    queued = conversation.conversation_runs.queued.first
    assert queued
    assert_equal next_ai.id, queued.speaker_space_membership_id
    assert_equal round.id, queued.conversation_round_id
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

    ConversationRun.where(conversation: conversation).delete_all
    ConversationRound.where(conversation: conversation).delete_all

    assert_difference -> { conversation.conversation_runs.count }, 1 do
      post regenerate_conversation_url(conversation), params: { message_id: tail.id }, as: :turbo_stream
    end

    assert_response :no_content

    # Deletes all messages after the last user message (the AI turn).
    assert_equal [user_msg.id], conversation.reload.messages.order(:seq, :id).pluck(:id)

    state = TurnScheduler.state(conversation.reload)
    assert_equal [ai1.id, ai2.id], state.round_queue_ids
    assert_equal ai1.id, state.current_speaker_id

    run = conversation.conversation_runs.order(:created_at, :id).last
    assert run.auto_response?
    assert_equal "queued", run.status
    assert_equal "auto_response", run.reason
    assert_equal "auto_response", run.debug["trigger"]
    assert_equal "turn_scheduler", run.debug["scheduled_by"]
    assert_equal state.current_round_id, run.conversation_round_id
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
    ConversationRound.where(conversation: conversation).delete_all

    assert_difference -> { conversation.conversation_runs.count }, 1 do
      post regenerate_conversation_url(conversation), params: { message_id: tail.id }, as: :turbo_stream
    end

    assert_response :no_content
    assert_equal [user_msg.id], conversation.reload.messages.order(:seq, :id).pluck(:id)

    state = TurnScheduler.state(conversation.reload)
    assert_equal [ai1.id, ai2.id], state.round_queue_ids

    run = conversation.conversation_runs.order(:created_at, :id).last
    assert_equal ai1.id, run.speaker_space_membership_id
    assert_equal state.current_round_id, run.conversation_round_id
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
    ConversationRound.where(conversation: conversation).delete_all

    assert_difference -> { conversation.conversation_runs.count }, 1 do
      post regenerate_conversation_url(conversation), params: { message_id: tail.id }, as: :turbo_stream
    end

    assert_response :no_content
    assert_equal [user_msg.id], conversation.reload.messages.order(:seq, :id).pluck(:id)

    state = TurnScheduler.state(conversation.reload)
    assert_equal 1, state.round_queue_ids.size
    assert_includes [ai1.id, ai2.id], state.round_queue_ids.first

    run = conversation.conversation_runs.order(:created_at, :id).last
    assert_equal state.current_round_id, run.conversation_round_id
    assert_equal state.current_speaker_id, run.speaker_space_membership_id
    assert_includes [ai1.id, ai2.id], run.speaker_space_membership_id
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
    ConversationRound.where(conversation: conversation).delete_all

    assert_difference -> { conversation.conversation_runs.count }, 1 do
      post regenerate_conversation_url(conversation), params: { message_id: tail.id }, as: :turbo_stream
    end

    assert_response :no_content
    assert_equal [user_msg.id], conversation.reload.messages.order(:seq, :id).pluck(:id)

    state = TurnScheduler.state(conversation.reload)
    assert_equal 1, state.round_queue_ids.size
    assert_includes [ai1.id, ai2.id], state.round_queue_ids.first

    run = conversation.conversation_runs.order(:created_at, :id).last
    assert_equal state.current_round_id, run.conversation_round_id
    assert_equal state.current_speaker_id, run.speaker_space_membership_id
    assert_includes [ai1.id, ai2.id], run.speaker_space_membership_id
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
    assert_turbo_stream(action: "replace", target: ActionView::RecordIdentifier.dom_id(conversation, :group_queue))
    assert_turbo_stream(action: "show_toast")
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
    assert_turbo_stream(action: "replace", target: ActionView::RecordIdentifier.dom_id(conversation, :group_queue))
    assert_turbo_stream(action: "show_toast")
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
    assert_turbo_stream(action: "replace", target: ActionView::RecordIdentifier.dom_id(conversation, :group_queue))
    assert_turbo_stream(action: "show_toast")
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
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, 'action="show_toast"'
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
    assert_turbo_stream(action: "replace", target: ActionView::RecordIdentifier.dom_id(conversation, :group_queue))
    assert_turbo_stream(action: "show_toast")
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
    ).execute

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
      success?: false,
      conversation: conversation,
      error: "Something went wrong",
      error_code: :error,
      deleted_message_ids: nil
    )

    Conversations::LastTurnRegenerator.any_instance.stubs(:execute).returns(error_result)

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

  test "stop returns turbo_stream that clears typing UI" do
    space = Spaces::Playground.create!(name: "Stop Turbo Stream Test", owner: users(:admin))
    space.space_memberships.grant_to(users(:admin), role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    conversation = space.conversations.create!(title: "Main", kind: "root")
    ai_membership = space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")

    run = ConversationRun.create!(
      kind: "auto_response",
      conversation: conversation,
      status: "running",
      reason: "test",
      speaker_space_membership_id: ai_membership.id,
      started_at: Time.current
    )

    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_typing)

    post stop_conversation_url(conversation), as: :turbo_stream

    assert_response :success
    assert_turbo_stream(action: "hide_typing_indicator")
    assert_turbo_stream(action: "show_stop_decision_alert")

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

  test "stop is idempotent - second execute does not change cancel_requested_at" do
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

    # First stop execute
    post stop_conversation_url(conversation)
    assert_response :no_content

    run.reload
    first_cancel_time = run.cancel_requested_at
    assert_not_nil first_cancel_time

    # Second stop execute (should not change the timestamp)
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
