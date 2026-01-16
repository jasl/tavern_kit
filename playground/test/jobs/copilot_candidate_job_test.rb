# frozen_string_literal: true

require "test_helper"

class CopilotCandidateJobTest < ActiveJob::TestCase
  setup do
    @admin = users(:admin)
    @space = Spaces::Playground.create!(name: "Copilot Job Test Space", owner: @admin)
    @conversation = @space.conversations.create!(title: "Main")

    @character = characters(:ready_v2)

    # Create owner membership with copilot setup (user + character)
    @participant =
      @space.space_memberships.create!(
        kind: "human",
        role: "owner",
        user: @admin,
        character: @character,
        copilot_mode: "none",
        position: 0
      )

    @ai_participant =
      @space.space_memberships.create!(
        kind: "character",
        role: "member",
        character: characters(:ready_v3),
        position: 1
      )

    @generation_id = SecureRandom.uuid
  end

  test "does not run for inactive spaces" do
    @space.archive!

    Messages::Broadcasts.expects(:broadcast_copilot_error)
      .with(@participant, generation_id: @generation_id, error: "Generation canceled: space is inactive.")
      .once

    assert_nothing_raised do
      CopilotCandidateJob.perform_now(
        @conversation.id, @participant.id,
        generation_id: @generation_id, index: 0
      )
    end
  end

  test "does not run for participants without user" do
    character_only = @ai_participant

    # Should not raise, just return early
    assert_nothing_raised do
      CopilotCandidateJob.perform_now(
        @conversation.id, character_only.id,
        generation_id: @generation_id, index: 0
      )
    end
  end

  test "does not run for participants without character" do
    # Remove the character from participant to simulate user without character
    @participant.update_columns(character_id: nil)

    # Should not raise, just return early
    assert_nothing_raised do
      CopilotCandidateJob.perform_now(
        @conversation.id, @participant.id,
        generation_id: @generation_id, index: 0
      )
    end
  end

  test "does not run for full copilot mode" do
    @participant.update!(copilot_mode: "full")

    # Should not raise, just return early
    assert_nothing_raised do
      CopilotCandidateJob.perform_now(
        @conversation.id, @participant.id,
        generation_id: @generation_id, index: 0
      )
    end
  end

  test "discards on record not found" do
    # Should discard without raising
    assert_nothing_raised do
      CopilotCandidateJob.perform_now(
        999_999, @participant.id,
        generation_id: @generation_id, index: 0
      )
    end
  end

  test "broadcasts candidate" do
    PromptBuilder.any_instance.stubs(:to_messages).returns([{ role: "user", content: "Hi" }])

    mock_provider = mock("provider")
    mock_client = mock("llm_client")
    mock_client.stubs(:provider).returns(mock_provider)
    mock_client.stubs(:chat).returns("Generated reply")
    mock_client.stubs(:last_usage).returns({ prompt_tokens: 10, completion_tokens: 5 })
    LLMClient.stubs(:new).returns(mock_client)

    Messages::Broadcasts.expects(:broadcast_copilot_candidate)
      .with(@participant, generation_id: @generation_id, index: 0, text: "Generated reply")
      .once

    CopilotCandidateJob.perform_now(
      @conversation.id, @participant.id,
      generation_id: @generation_id, index: 0
    )
  end

  test "multiple parallel jobs broadcast multiple candidates" do
    PromptBuilder.any_instance.stubs(:to_messages).returns([{ role: "user", content: "Hi" }])

    mock_provider = mock("provider")
    mock_client = mock("llm_client")
    mock_client.stubs(:provider).returns(mock_provider)
    mock_client.stubs(:chat).returns("Candidate")
    mock_client.stubs(:last_usage).returns({ prompt_tokens: 10, completion_tokens: 5 })
    LLMClient.stubs(:new).returns(mock_client)

    # Expect candidates for all 3 jobs (frontend tracks completion)
    Messages::Broadcasts.expects(:broadcast_copilot_candidate).times(3)

    # Simulate 3 parallel jobs completing
    3.times do |i|
      CopilotCandidateJob.perform_now(
        @conversation.id, @participant.id,
        generation_id: @generation_id, index: i
      )
    end
  end

  test "broadcasts error when provider is unconfigured" do
    PromptBuilder.any_instance.stubs(:to_messages).returns([{ role: "user", content: "Hi" }])

    mock_client = mock("llm_client")
    mock_client.stubs(:provider).returns(nil)
    LLMClient.stubs(:new).returns(mock_client)

    Messages::Broadcasts.expects(:broadcast_copilot_error)
      .with(@participant, generation_id: @generation_id, error: "No LLM provider configured")
      .once

    CopilotCandidateJob.perform_now(
      @conversation.id, @participant.id,
      generation_id: @generation_id, index: 0
    )
  end

  test "broadcasts error on unexpected exception to avoid stuck generation" do
    PromptBuilder.any_instance.stubs(:to_messages).returns([{ role: "user", content: "Hi" }])

    mock_provider = mock("provider")
    mock_client = mock("llm_client")
    mock_client.stubs(:provider).returns(mock_provider)
    mock_client.stubs(:chat).raises(RuntimeError, "Boom")
    LLMClient.stubs(:new).returns(mock_client)

    Messages::Broadcasts.expects(:broadcast_copilot_error)
      .with(@participant, generation_id: @generation_id, error: "Generation failed: Boom")
      .once

    CopilotCandidateJob.perform_now(
      @conversation.id, @participant.id,
      generation_id: @generation_id, index: 0
    )
  end

  test "records token usage to conversation statistics" do
    # Reset token counters
    @conversation.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)

    PromptBuilder.any_instance.stubs(:to_messages).returns([{ role: "user", content: "Hi" }])

    mock_provider = mock("provider")
    mock_client = mock("llm_client")
    mock_client.stubs(:provider).returns(mock_provider)
    mock_client.stubs(:chat).returns("Generated reply")
    mock_client.stubs(:last_usage).returns({ prompt_tokens: 100, completion_tokens: 50 })
    LLMClient.stubs(:new).returns(mock_client)

    Messages::Broadcasts.stubs(:broadcast_copilot_candidate)

    CopilotCandidateJob.perform_now(
      @conversation.id, @participant.id,
      generation_id: @generation_id, index: 0
    )

    @conversation.reload
    assert_equal 100, @conversation.prompt_tokens_total
    assert_equal 50, @conversation.completion_tokens_total
  end
end
