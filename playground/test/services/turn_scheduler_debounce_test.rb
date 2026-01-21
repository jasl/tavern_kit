# frozen_string_literal: true

require "test_helper"

class TurnSchedulerDebounceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:admin)
    @space =
      Spaces::Playground.create!(
        name: "Debounce Test Space",
        owner: @user,
        reply_order: "natural",
        during_generation_user_input_policy: "queue",
        user_turn_debounce_ms: 2000
      )

    @conversation = @space.conversations.create!(title: "Main")

    @human = @space.space_memberships.create!(
      kind: "human",
      role: "owner",
      user: @user,
      position: 0
    )
    @ai = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      position: 1
    )

    TurnScheduler::Broadcasts.stubs(:queue_updated)
    Message.any_instance.stubs(:notify_scheduler_turn_complete)
    clear_enqueued_jobs
  end

  test "debounce: rapid user messages collapse into one active queued run" do
    t0 = Time.current.change(usec: 0)

    run1 = nil
    travel_to t0 do
      msg1 = @conversation.messages.create!(space_membership: @human, role: "user", content: "One")
      TurnScheduler::Commands::StartRound.execute(conversation: @conversation, trigger_message: msg1, is_user_input: true)

      @conversation.reload
      run1 = @conversation.conversation_runs.queued.first
      assert_not_nil run1
      assert_in_delta t0 + 2, run1.run_after, 0.1
    end

    t1 = t0 + 1
    travel_to t1 do
      @conversation.cancel_all_queued_runs!(reason: "debounce_test")
      TurnScheduler.stop!(@conversation)

      msg2 = @conversation.messages.create!(space_membership: @human, role: "user", content: "Two")
      TurnScheduler::Commands::StartRound.execute(conversation: @conversation, trigger_message: msg2, is_user_input: true)
    end

    assert_equal "canceled", run1.reload.status

    @conversation.reload
    active = @conversation.conversation_runs.active
    assert_equal 1, active.count

    run2 = active.first
    assert run2.queued?
    assert_in_delta t1 + 2, run2.run_after, 0.1
  end
end
