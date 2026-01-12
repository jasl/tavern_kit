# frozen_string_literal: true

require "test_helper"

class SpaceMembershipTest < ActiveSupport::TestCase
  fixtures :users, :characters, :llm_providers

  test "kind=human requires user_id" do
    space = Spaces::Playground.create!(name: "Validation Space", owner: users(:admin))

    membership = space.space_memberships.new(kind: "human")
    assert_not membership.valid?
    assert_includes membership.errors[:user_id], "must be present for human memberships"
  end

  test "kind=character requires character_id and forbids user_id" do
    space = Spaces::Playground.create!(name: "Validation Space", owner: users(:admin))

    membership = space.space_memberships.new(kind: "character", user: users(:admin))
    assert_not membership.valid?
    assert_includes membership.errors[:character_id], "must be present for character memberships"
    assert_includes membership.errors[:user_id], "must be blank for character memberships"
  end

  test "allows a human membership to also carry a character persona" do
    space = Spaces::Playground.create!(name: "Validation Space", owner: users(:admin))

    membership =
      space.space_memberships.create!(
        kind: "human",
        user: users(:member),
        character: characters(:ready_v2),
        role: "member"
      )

    assert membership.kind_human?
    assert membership.user?
    assert membership.character?
    assert membership.copilot_none?
  end

  test "requires user+character for full copilot" do
    space = Spaces::Playground.create!(name: "Validation Space", owner: users(:admin))

    missing_character = space.space_memberships.new(kind: "human", user: users(:member), copilot_mode: "full")
    assert_not missing_character.valid?
    assert_includes missing_character.errors[:copilot_mode], "requires both a user and a character"

    ok =
      space.space_memberships.create!(
        kind: "human",
        user: users(:member),
        character: characters(:ready_v2),
        copilot_mode: "full",
        role: "member"
      )
    assert ok.copilot_full?
  end

  test "playground spaces allow only one human membership" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.create!(kind: "human", user: users(:admin), role: "owner")

    second = space.space_memberships.new(kind: "human", user: users(:member), role: "member")
    assert_not second.valid?
    assert_includes second.errors[:kind], "only one human membership is allowed in a playground space"
  end

  test "enabling full copilot without steps defaults to a safe budget" do
    space = Spaces::Playground.create!(name: "Copilot Budget Space", owner: users(:admin))

    membership =
      space.space_memberships.create!(
        kind: "human",
        user: users(:member),
        character: characters(:ready_v2),
        copilot_mode: "none",
        role: "member"
      )

    membership.update!(copilot_mode: "full")

    assert membership.reload.copilot_full?
    assert_equal SpaceMembership::DEFAULT_COPILOT_STEPS, membership.copilot_remaining_steps
  end

  test "full copilot enforces a 1..10 step budget" do
    space = Spaces::Playground.create!(name: "Copilot Budget Space", owner: users(:admin))

    membership =
      space.space_memberships.new(
        kind: "human",
        user: users(:member),
        character: characters(:ready_v2),
        copilot_mode: "full",
        copilot_remaining_steps: 11,
        role: "member"
      )

    assert_not membership.valid?
    assert membership.errors[:copilot_remaining_steps].any?
  end

  test "provider_identification falls back to settings when effective provider is nil" do
    space = Spaces::Playground.create!(name: "Provider Space", owner: users(:admin))

    membership =
      space.space_memberships.create!(
        kind: "human",
        user: users(:admin),
        role: "member"
      )

    membership.define_singleton_method(:effective_llm_provider) { nil }
    assert_equal "openai_compatible", membership.provider_identification
  end

  test "effective_llm_provider falls back when selected provider is disabled" do
    default_provider = llm_providers(:mock_local)
    Setting.set("llm.default_provider_id", default_provider.id)

    disabled_provider =
      LLMProvider.create!(
        name: "Disabled Provider",
        identification: "openai_compatible",
        base_url: "http://example.test/v1",
        model: "test",
        streamable: true,
        supports_logprobs: false,
        disabled: true,
      )

    space = Spaces::Playground.create!(name: "Provider Space", owner: users(:admin))
    membership = space.space_memberships.create!(kind: "human", user: users(:admin), role: "member", llm_provider: disabled_provider)

    assert_equal default_provider, membership.effective_llm_provider
  end

  test "membership change can auto-skip when the member is current speaker" do
    user = users(:admin)
    space =
      Spaces::Playground.create!(
        name: "Membership Auto Skip Space",
        owner: user,
        reply_order: "list"
      )
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: user, position: 0)
    ai1 =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v2),
        position: 1
      )
    ai2 =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v3),
        position: 2
      )

    conversation.update!(
      scheduling_state: "ai_generating",
      current_round_id: SecureRandom.uuid,
      current_speaker_id: ai1.id,
      round_position: 0,
      round_spoken_ids: [],
      round_queue_ids: [ai1.id, ai2.id]
    )

    run1 =
      ConversationRun.create!(
        conversation: conversation,
        status: "queued",
        kind: "auto_response",
        reason: "auto_response",
        speaker_space_membership_id: ai1.id,
        run_after: Time.current
      )

    TurnScheduler::Broadcasts.stubs(:queue_updated)

    ai1.update!(participation: "muted")
    ai1.send(:notify_scheduler_if_participation_changed)

    assert_equal "canceled", run1.reload.status

    conversation.reload
    assert_equal ai2.id, conversation.current_speaker_id
    assert_equal 1, conversation.round_position

    run2 = conversation.conversation_runs.queued.first
    assert_not_nil run2
    assert_equal ai2.id, run2.speaker_space_membership_id
  end

  test "membership change can request cancel and auto-skip when the member is the running current speaker" do
    user = users(:admin)
    space =
      Spaces::Playground.create!(
        name: "Membership Auto Skip Running Space",
        owner: user,
        reply_order: "list"
      )
    conversation = space.conversations.create!(title: "Main")

    space.space_memberships.create!(kind: "human", role: "owner", user: user, position: 0)
    ai1 =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v2),
        position: 1
      )
    ai2 =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v3),
        position: 2
      )

    conversation.update!(
      scheduling_state: "ai_generating",
      current_round_id: SecureRandom.uuid,
      current_speaker_id: ai1.id,
      round_position: 0,
      round_spoken_ids: [],
      round_queue_ids: [ai1.id, ai2.id]
    )

    run1 =
      ConversationRun.create!(
        conversation: conversation,
        status: "running",
        kind: "auto_response",
        reason: "auto_response",
        speaker_space_membership_id: ai1.id,
        started_at: Time.current,
        heartbeat_at: Time.current,
        run_after: Time.current
      )

    TurnScheduler::Broadcasts.stubs(:queue_updated)
    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_typing)

    ai1.update!(participation: "muted")
    ai1.send(:notify_scheduler_if_participation_changed)

    assert_not_nil run1.reload.cancel_requested_at

    conversation.reload
    assert_equal ai2.id, conversation.current_speaker_id
    assert_equal 1, conversation.round_position

    run2 = conversation.conversation_runs.queued.first
    assert_not_nil run2
    assert_equal ai2.id, run2.speaker_space_membership_id
  end
end
