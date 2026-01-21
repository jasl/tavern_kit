# frozen_string_literal: true

require "test_helper"

class Conversations::RunExecutor::RunPersistenceEventsTest < ActiveSupport::TestCase
  test "finalize_success! emits conversation_run.succeeded" do
    space = Spaces::Playground.create!(name: "RunPersistence Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    speaker =
      space.space_memberships.create!(
        kind: "character",
        character: characters(:ready_v3),
        role: "member",
        position: 0
      )

    run =
      ConversationRun.create!(
        conversation: conversation,
        speaker_space_membership: speaker,
        status: "running",
        kind: "auto_response",
        reason: "test",
        debug: { "trigger_message_id" => 123 }
      )

    persistence = Conversations::RunExecutor::RunPersistence.new(run: run, conversation: conversation, space: space, speaker: speaker)

    assert_difference -> { ConversationEvent.where(event_name: "conversation_run.succeeded").count }, 1 do
      persistence.finalize_success!(llm_client: Object.new)
    end

    event = ConversationEvent.where(event_name: "conversation_run.succeeded").order(id: :desc).first
    assert_equal conversation.id, event.conversation_id
    assert_equal space.id, event.space_id
    assert_equal run.id, event.conversation_run_id
    assert_equal "auto_response", event.reason
    assert_equal 123, event.trigger_message_id
  end

  test "finalize_failed! emits conversation_run.failed and failure_handled" do
    space = Spaces::Playground.create!(name: "RunPersistence Space 2", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    speaker =
      space.space_memberships.create!(
        kind: "character",
        character: characters(:ready_v3),
        role: "member",
        position: 0
      )

    run =
      ConversationRun.create!(
        conversation: conversation,
        speaker_space_membership: speaker,
        status: "running",
        kind: "auto_response",
        reason: "test",
        debug: { "trigger_message_id" => 456 }
      )

    persistence = Conversations::RunExecutor::RunPersistence.new(run: run, conversation: conversation, space: space, speaker: speaker)

    assert_difference -> { ConversationEvent.where(event_name: "conversation_run.failed").count }, 1 do
      assert_difference -> { ConversationEvent.where(event_name: "turn_scheduler.failure_handled").count }, 1 do
        persistence.finalize_failed!(StandardError.new("boom"), code: "context_builder_error")
      end
    end

    event = ConversationEvent.where(event_name: "conversation_run.failed").order(id: :desc).first
    assert_equal run.id, event.conversation_run_id
    assert_equal 456, event.trigger_message_id
    assert_equal "context_builder_error", event.reason
    assert_equal "running", event.payload["previous_status"]
  end
end
