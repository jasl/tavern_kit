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

    # Should not raise, just return early
    assert_nothing_raised do
      CopilotCandidateJob.perform_now(@conversation.id, @participant.id, generation_id: @generation_id)
    end
  end

  test "does not run for participants without user" do
    character_only = @ai_participant

    # Should not raise, just return early
    assert_nothing_raised do
      CopilotCandidateJob.perform_now(@conversation.id, character_only.id, generation_id: @generation_id)
    end
  end

  test "does not run for participants without character" do
    # Remove the character from participant to simulate user without character
    @participant.update_columns(character_id: nil)

    # Should not raise, just return early
    assert_nothing_raised do
      CopilotCandidateJob.perform_now(@conversation.id, @participant.id, generation_id: @generation_id)
    end
  end

  test "does not run for full copilot mode" do
    @participant.update!(copilot_mode: "full")

    # Should not raise, just return early
    assert_nothing_raised do
      CopilotCandidateJob.perform_now(@conversation.id, @participant.id, generation_id: @generation_id)
    end
  end

  test "discards on record not found" do
    # Should discard without raising
    assert_nothing_raised do
      CopilotCandidateJob.perform_now(999_999, @participant.id, generation_id: @generation_id)
    end
  end

  test "broadcasts candidates and complete" do
    PromptBuilder.any_instance.stubs(:to_messages).returns([{ role: "user", content: "Hi" }])

    mock_provider = mock("provider")
    mock_client = mock("llm_client")
    mock_client.stubs(:provider).returns(mock_provider)
    mock_client.stubs(:chat).returns("One", "Two")
    LLMClient.stubs(:new).returns(mock_client)

    Message::Broadcasts.expects(:broadcast_copilot_candidate)
      .with(@participant, generation_id: @generation_id, index: 0, text: "One")
      .once
    Message::Broadcasts.expects(:broadcast_copilot_candidate)
      .with(@participant, generation_id: @generation_id, index: 1, text: "Two")
      .once
    Message::Broadcasts.expects(:broadcast_copilot_complete)
      .with(@participant, generation_id: @generation_id)
      .once

    CopilotCandidateJob.perform_now(@conversation.id, @participant.id, generation_id: @generation_id, candidate_count: 2)
  end

  test "clamps candidate count to 1-4" do
    PromptBuilder.any_instance.stubs(:to_messages).returns([{ role: "user", content: "Hi" }])

    mock_provider = mock("provider")
    mock_client = mock("llm_client")
    mock_client.stubs(:provider).returns(mock_provider)
    mock_client.stubs(:chat).returns("Candidate")
    LLMClient.stubs(:new).returns(mock_client)

    Message::Broadcasts.expects(:broadcast_copilot_candidate)
      .with(@participant, generation_id: @generation_id, index: 0, text: "Candidate")
      .once
    Message::Broadcasts.expects(:broadcast_copilot_candidate)
      .with(@participant, generation_id: @generation_id, index: 1, text: "Candidate")
      .once
    Message::Broadcasts.expects(:broadcast_copilot_candidate)
      .with(@participant, generation_id: @generation_id, index: 2, text: "Candidate")
      .once
    Message::Broadcasts.expects(:broadcast_copilot_candidate)
      .with(@participant, generation_id: @generation_id, index: 3, text: "Candidate")
      .once
    Message::Broadcasts.expects(:broadcast_copilot_complete)
      .with(@participant, generation_id: @generation_id)
      .once

    CopilotCandidateJob.perform_now(@conversation.id, @participant.id, generation_id: @generation_id, candidate_count: 10)
  end

  test "broadcasts error when provider is unconfigured" do
    PromptBuilder.any_instance.stubs(:to_messages).returns([{ role: "user", content: "Hi" }])

    mock_client = mock("llm_client")
    mock_client.stubs(:provider).returns(nil)
    LLMClient.stubs(:new).returns(mock_client)

    Message::Broadcasts.expects(:broadcast_copilot_error)
      .with(@participant, generation_id: @generation_id, error: "No LLM provider configured")
      .once

    CopilotCandidateJob.perform_now(@conversation.id, @participant.id, generation_id: @generation_id)
  end
end
