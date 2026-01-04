# frozen_string_literal: true

require "test_helper"

class MockLLM::V1::ModelsControllerTest < ActionDispatch::IntegrationTest
  test "models returns an OpenAI-compatible model list" do
    get "/mock_llm/v1/models"

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "list", body.fetch("object")
    assert_equal ["mock"], body.fetch("data").map { |m| m.fetch("id") }
  end
end
