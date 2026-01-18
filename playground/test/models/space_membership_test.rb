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

  test "copilot mode works for human with character" do
    space = Spaces::Playground.create!(name: "Validation Space", owner: users(:admin))

    # With character (no custom persona) should succeed
    with_character =
      space.space_memberships.create!(
        kind: "human",
        user: users(:member),
        character: characters(:ready_v2),
        copilot_mode: "full",
        role: "member"
      )
    assert with_character.copilot_full?
    assert with_character.human_with_persona?
  end

  test "copilot mode works for pure human without character or persona" do
    space = Spaces::Playground.create!(name: "Copilot Pure Human Space", owner: users(:admin))

    # Pure human without character or persona should succeed (like SillyTavern)
    pure_human =
      space.space_memberships.create!(
        kind: "human",
        user: users(:member),
        copilot_mode: "full",
        role: "member"
      )
    assert pure_human.copilot_full?
    assert pure_human.pure_human?
    assert pure_human.copilot_capable?
  end

  test "copilot mode works for pure human with custom persona" do
    space = Spaces::Playground.create!(name: "Copilot Persona Space", owner: users(:admin))

    # Pure human with custom persona should succeed
    with_persona =
      space.space_memberships.create!(
        kind: "human",
        user: users(:member),
        persona: "A friendly chat participant who enjoys discussing technology.",
        copilot_mode: "full",
        role: "member"
      )
    assert with_persona.copilot_full?
    assert with_persona.pure_human?
    assert with_persona.copilot_capable?
    assert_equal "A friendly chat participant who enjoys discussing technology.", with_persona.effective_persona
  end

  test "copilot_capable? returns true for all human memberships" do
    space = Spaces::Playground.create!(name: "Copilot Capable Space", owner: users(:admin))

    # All human memberships are copilot capable (persona is optional)
    pure_human = space.space_memberships.create!(
      kind: "human",
      user: users(:admin),
      role: "owner"
    )
    assert pure_human.copilot_capable?

    # Human with character is also copilot capable
    space2 = Spaces::Playground.create!(name: "Copilot Capable Space 2", owner: users(:member))
    with_character = space2.space_memberships.create!(
      kind: "human",
      user: users(:member),
      character: characters(:ready_v2),
      role: "owner"
    )
    assert with_character.copilot_capable?

    # AI character is NOT copilot capable (it's autonomous, not user-controlled)
    ai_char = space.space_memberships.create!(
      kind: "character",
      character: characters(:ready_v3),
      role: "member"
    )
    assert_not ai_char.copilot_capable?
  end

  test "effective_talkativeness_factor falls back to character card extensions.talkativeness" do
    user = users(:admin)
    space = Spaces::Playground.create!(name: "Talkativeness Space", owner: user)

    character =
      Character.create!(
        name: "Talkative",
        user: user,
        status: "ready",
        visibility: "private",
        spec_version: 2,
        file_sha256: "talkative_#{SecureRandom.hex(8)}",
        data: {
          name: "Talkative",
          group_only_greetings: [],
          extensions: { talkativeness: "0.9" },
        }
      )

    membership =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: character,
        position: 0,
        talkativeness_factor: nil
      )

    assert_in_delta 0.9, membership.effective_talkativeness_factor, 0.0001
  end

  test "effective_talkativeness_factor treats any non-nil talkativeness_factor as override (even 0.5)" do
    user = users(:admin)
    space = Spaces::Playground.create!(name: "Talkativeness Default Override Space", owner: user)

    character =
      Character.create!(
        name: "Talkative",
        user: user,
        status: "ready",
        visibility: "private",
        spec_version: 2,
        file_sha256: "talkative_default_override_#{SecureRandom.hex(8)}",
        data: {
          name: "Talkative",
          group_only_greetings: [],
          extensions: { talkativeness: 1.0 },
        }
      )

    membership =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: character,
        position: 0,
        talkativeness_factor: SpaceMembership::DEFAULT_TALKATIVENESS_FACTOR
      )

    assert_in_delta 0.5, membership.effective_talkativeness_factor, 0.0001
  end

  test "effective_talkativeness_factor falls back to default when membership and character card are unset" do
    user = users(:admin)
    space = Spaces::Playground.create!(name: "Talkativeness Default Fallback Space", owner: user)

    character =
      Character.create!(
        name: "No Talkativeness",
        user: user,
        status: "ready",
        visibility: "private",
        spec_version: 2,
        file_sha256: "no_talkativeness_#{SecureRandom.hex(8)}",
        data: {
          name: "No Talkativeness",
          group_only_greetings: [],
          extensions: {},
        }
      )

    membership =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: character,
        position: 0,
        talkativeness_factor: nil
      )

    assert_in_delta SpaceMembership::DEFAULT_TALKATIVENESS_FACTOR, membership.effective_talkativeness_factor, 0.0001
  end

  test "effective_talkativeness_factor honors per-membership overrides" do
    user = users(:admin)
    space = Spaces::Playground.create!(name: "Talkativeness Override Space", owner: user)

    character =
      Character.create!(
        name: "Talkative",
        user: user,
        status: "ready",
        visibility: "private",
        spec_version: 2,
        file_sha256: "talkative_override_#{SecureRandom.hex(8)}",
        data: {
          name: "Talkative",
          group_only_greetings: [],
          extensions: { talkativeness: 0.9 },
        }
      )

    membership =
      space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: character,
        position: 0,
        talkativeness_factor: 0.2
      )

    assert_in_delta 0.2, membership.effective_talkativeness_factor, 0.0001
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

    # Test with character persona
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

  test "enabling full copilot for pure human with persona defaults to a safe budget" do
    space = Spaces::Playground.create!(name: "Copilot Budget Space Pure Human", owner: users(:admin))

    # Test with custom persona (no character)
    membership =
      space.space_memberships.create!(
        kind: "human",
        user: users(:member),
        persona: "A helpful participant",
        copilot_mode: "none",
        role: "member"
      )

    membership.update!(copilot_mode: "full")

    assert membership.reload.copilot_full?
    assert_equal SpaceMembership::DEFAULT_COPILOT_STEPS, membership.copilot_remaining_steps
    assert membership.pure_human?
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

    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "ai_generating", current_position: 0)
    round.participants.create!(space_membership: ai1, position: 0, status: "pending")
    round.participants.create!(space_membership: ai2, position: 1, status: "pending")

    run1 =
      ConversationRun.create!(
        conversation: conversation,
        conversation_round_id: round.id,
        status: "queued",
        kind: "auto_response",
        reason: "auto_response",
        speaker_space_membership_id: ai1.id,
        run_after: Time.current,
        debug: {
          trigger: "auto_response",
          scheduled_by: "turn_scheduler",
          round_id: round.id,
        }
      )

    TurnScheduler::Broadcasts.stubs(:queue_updated)

    ai1.update!(participation: "muted")
    ai1.send(:notify_scheduler_if_participation_changed)

    assert_equal "canceled", run1.reload.status

    state = TurnScheduler.state(conversation.reload)
    assert_equal ai2.id, state.current_speaker_id
    assert_equal 1, state.round_position

    run2 = conversation.conversation_runs.queued.first
    assert_not_nil run2
    assert_equal ai2.id, run2.speaker_space_membership_id
    assert_equal round.id, run2.conversation_round_id
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

    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "ai_generating", current_position: 0)
    round.participants.create!(space_membership: ai1, position: 0, status: "pending")
    round.participants.create!(space_membership: ai2, position: 1, status: "pending")

    run1 =
      ConversationRun.create!(
        conversation: conversation,
        conversation_round_id: round.id,
        status: "running",
        kind: "auto_response",
        reason: "auto_response",
        speaker_space_membership_id: ai1.id,
        started_at: Time.current,
        heartbeat_at: Time.current,
        run_after: Time.current,
        debug: {
          trigger: "auto_response",
          scheduled_by: "turn_scheduler",
          round_id: round.id,
        }
      )

    TurnScheduler::Broadcasts.stubs(:queue_updated)
    ConversationChannel.stubs(:broadcast_stream_complete)
    ConversationChannel.stubs(:broadcast_typing)

    ai1.update!(participation: "muted")
    ai1.send(:notify_scheduler_if_participation_changed)

    assert_not_nil run1.reload.cancel_requested_at

    state = TurnScheduler.state(conversation.reload)
    assert_equal ai2.id, state.current_speaker_id
    assert_equal 1, state.round_position

    run2 = conversation.conversation_runs.queued.first
    assert_not_nil run2
    assert_equal ai2.id, run2.speaker_space_membership_id
    assert_equal round.id, run2.conversation_round_id
  end

  test "membership change does not auto-skip when scheduler is paused" do
    user = users(:admin)
    space =
      Spaces::Playground.create!(
        name: "Membership Pause Space",
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

    round = ConversationRound.create!(conversation: conversation, status: "active", scheduling_state: "paused", current_position: 0)
    round.participants.create!(space_membership: ai1, position: 0, status: "pending")
    round.participants.create!(space_membership: ai2, position: 1, status: "pending")

    TurnScheduler::Commands::SkipCurrentSpeaker.expects(:call).never
    TurnScheduler::Broadcasts.expects(:queue_updated).with(conversation).at_least_once

    ai1.update!(participation: "muted")
    ai1.send(:notify_scheduler_if_participation_changed)

    state = TurnScheduler.state(conversation.reload)
    assert_equal "paused", state.scheduling_state
    assert_equal ai1.id, state.current_speaker_id
  end
end
