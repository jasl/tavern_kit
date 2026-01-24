# frozen_string_literal: true

require "test_helper"

class Conversations::AutoCandidateGeneratorTest < ActiveSupport::TestCase
  test "generate_single uses a default max_tokens when settings are unset" do
    space = Spaces::Playground.create!(name: "Auto Candidate Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    human = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2))

    generator = Conversations::AutoCandidateGenerator.new(conversation: conversation, participant: human, generation_id: "g-1", index: 0)

    fake_client =
      Class.new do
        attr_reader :provider, :last_usage, :last_chat_max_tokens

        def initialize(provider:)
          @provider = provider
          @last_usage = nil
          @last_chat_max_tokens = nil
        end

        def chat(messages:, max_tokens: nil, **)
          @last_chat_max_tokens = max_tokens
          "Hello from fake client"
        end
      end.new(provider: llm_providers(:mock_local))

    broadcasts = []

    AutoChannel.stubs(:broadcast_to).with do |_membership, payload|
      broadcasts << payload
      true
    end

    generator.stubs(:build_messages).returns([{ role: "user", content: "Hi" }])
    generator.stubs(:build_client).returns(fake_client)
    generator.stubs(:max_response_tokens).returns(nil)

    generator.generate_single

    assert_equal Conversations::AutoCandidateGenerator::DEFAULT_CANDIDATE_MAX_TOKENS, fake_client.last_chat_max_tokens
    assert_equal 1, broadcasts.size
    assert_equal "auto_candidate", broadcasts.first[:type]
    assert_equal "Hello from fake client", broadcasts.first[:text]
  end

  test "generate_single broadcasts an error when the model returns blank content" do
    space = Spaces::Playground.create!(name: "Auto Candidate Blank Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")

    human = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2))

    generator = Conversations::AutoCandidateGenerator.new(conversation: conversation, participant: human, generation_id: "g-2", index: 0)

    fake_client =
      Class.new do
        attr_reader :provider, :last_usage

        def initialize(provider:)
          @provider = provider
          @last_usage = nil
        end

        def chat(messages:, max_tokens: nil, **)
          "   "
        end
      end.new(provider: llm_providers(:mock_local))

    broadcasts = []

    AutoChannel.stubs(:broadcast_to).with do |_membership, payload|
      broadcasts << payload
      true
    end

    generator.stubs(:build_messages).returns([{ role: "user", content: "Hi" }])
    generator.stubs(:build_client).returns(fake_client)

    generator.generate_single

    assert_equal 1, broadcasts.size
    assert_equal "auto_candidate_error", broadcasts.first[:type]
    assert_match(/empty response/i, broadcasts.first[:error].to_s)
  end
end
