# frozen_string_literal: true

require "test_helper"

class MockLLM::V1::ChatCompletionsControllerTest < ActionDispatch::IntegrationTest
  test "non-streaming chat completions returns OpenAI-compatible JSON" do
    post "/mock_llm/v1/chat/completions",
         params: {
           model: "mock",
           messages: [{ role: "user", content: "Hello" }],
         },
         as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "chat.completion", body.fetch("object")
    assert_equal "mock", body.fetch("model")
    assert_equal "assistant", body.dig("choices", 0, "message", "role")
    assert_includes body.dig("choices", 0, "message", "content").to_s, "Hello"
    assert body.fetch("usage").is_a?(Hash)
  end

  test "streaming chat completions returns OpenAI-style SSE" do
    post "/mock_llm/v1/chat/completions",
         params: {
           model: "mock",
           stream: true,
           stream_options: { include_usage: true },
           messages: [{ role: "user", content: "Hello" }],
         },
         as: :json

    assert_response :success
    assert_includes response.headers.fetch("Content-Type"), "text/event-stream"

    # In test, the full SSE body is available as a single string.
    assert_includes response.body, "data:"
    assert_includes response.body, "data: [DONE]"
  end
end
