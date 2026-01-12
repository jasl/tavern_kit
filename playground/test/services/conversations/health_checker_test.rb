# frozen_string_literal: true

require "test_helper"

class Conversations::HealthCheckerTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
  end

  test "healthy when no runs and no auto scheduling expected" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    result = Conversations::HealthChecker.check(conversation)

    assert_equal "healthy", result[:status]
    assert_equal "none", result[:action]
  end

  test "reports stuck when running run has no heartbeat for too long" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    travel_to Time.current.change(usec: 0) do
      started_at = Time.current - (Conversations::HealthChecker::STUCK_THRESHOLD + 1.second)
      run = ConversationRun.create!(
        conversation: conversation,
        speaker_space_membership_id: speaker.id,
        kind: "auto_response",
        status: "running",
        reason: "test",
        started_at: started_at,
        heartbeat_at: started_at
      )

      result = Conversations::HealthChecker.check(conversation)

      assert_equal "stuck", result[:status]
      assert_equal "retry", result[:action]
      assert_equal run.id, result.dig(:details, :run_id)
    end
  end

  test "reports stuck when queued run has been waiting too long" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    travel_to Time.current.change(usec: 0) do
      run = ConversationRun.create!(
        conversation: conversation,
        speaker_space_membership_id: speaker.id,
        kind: "auto_response",
        status: "queued",
        reason: "test",
        created_at: Time.current - (Conversations::HealthChecker::STUCK_THRESHOLD + 1.second),
        updated_at: Time.current - (Conversations::HealthChecker::STUCK_THRESHOLD + 1.second)
      )

      result = Conversations::HealthChecker.check(conversation)

      assert_equal "stuck", result[:status]
      assert_equal "retry", result[:action]
      assert_equal run.id, result.dig(:details, :run_id)
    end
  end

  test "reports failed when a recent failed run exists" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    travel_to Time.current.change(usec: 0) do
      run = ConversationRun.create!(
        conversation: conversation,
        speaker_space_membership_id: speaker.id,
        kind: "auto_response",
        status: "failed",
        reason: "test",
        finished_at: Time.current - 10.seconds,
        error: { "code" => "test_error" }
      )

      result = Conversations::HealthChecker.check(conversation)

      assert_equal "failed", result[:status]
      assert_equal "retry", result[:action]
      assert_equal run.id, result.dig(:details, :run_id)
    end
  end

  test "reports idle_unexpected when auto mode enabled but no run exists" do
    space = Spaces::Playground.create!(name: "HealthChecker Space", owner: @user, reply_order: "list")
    space.space_memberships.create!(kind: "human", role: "owner", user: @user, position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")
    conversation.start_auto_mode!(rounds: 2)

    result = Conversations::HealthChecker.check(conversation)

    assert_equal "idle_unexpected", result[:status]
    assert_equal "generate", result[:action]
    assert_equal speaker.id, result.dig(:details, :suggested_speaker_id)
  end
end

