# frozen_string_literal: true

require "test_helper"

class LLMClientTest < ActiveSupport::TestCase
  FakeChatResult = Struct.new(:content, :usage, :logprobs, keyword_init: true)

  class FakeSimpleInferenceClient
    attr_reader :calls

    def initialize(result:, chunks: nil)
      @result = result
      @chunks = chunks
      @calls = []
    end

    def chat(**kwargs, &block)
      @calls << kwargs
      Array(@chunks).each { |chunk| block.call(chunk) } if block && @chunks
      @result
    end
  end

  test "chat delegates to SimpleInference and stores usage/logprobs" do
    provider = llm_providers(:mock_local)

    result =
      FakeChatResult.new(
        content: "Hello (SimpleInference)",
        usage: { prompt_tokens: 1, completion_tokens: 2, total_tokens: 3 },
        logprobs: [{ "token" => "Hello", "logprob" => -0.1 }]
      )

    fake_http_client = FakeSimpleInferenceClient.new(result: result)

    client = LLMClient.new(provider: provider)
    client.stubs(:build_client).returns(fake_http_client)

    out = client.chat(messages: [{ role: "user", content: "Hi" }], model: "mock", request_logprobs: true)

    assert_equal "Hello (SimpleInference)", out
    assert_equal({ prompt_tokens: 1, completion_tokens: 2, total_tokens: 3 }, client.last_usage)
    assert_equal([{ "token" => "Hello", "logprob" => -0.1 }], client.last_logprobs)

    assert_equal false, fake_http_client.calls.last[:stream]
    assert_equal false, fake_http_client.calls.last[:request_logprobs]
  end

  test "chat streams deltas when a block is given and requests usage in the final chunk" do
    provider = llm_providers(:mock_local)
    provider.update!(supports_logprobs: true)

    result =
      FakeChatResult.new(
        content: "Hello",
        usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
        logprobs: []
      )

    fake_http_client = FakeSimpleInferenceClient.new(result: result, chunks: %w[Hel lo])

    client = LLMClient.new(provider: provider)
    client.stubs(:build_client).returns(fake_http_client)

    streamed = +""
    out =
      client.chat(messages: [{ role: "user", content: "Hi" }], model: "mock", request_logprobs: true) do |chunk|
        streamed << chunk
      end

    assert_equal "Hello", streamed
    assert_equal "Hello", out
    assert_equal({ prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }, client.last_usage)

    assert_equal true, fake_http_client.calls.last[:stream]
    assert_equal true, fake_http_client.calls.last[:include_usage]
    assert_equal true, fake_http_client.calls.last[:request_logprobs]
  end
end
