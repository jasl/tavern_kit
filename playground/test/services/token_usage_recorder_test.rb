# frozen_string_literal: true

require "test_helper"

class TokenUsageRecorderTest < ActiveSupport::TestCase
  setup do
    @admin = users(:admin)
    @space = Spaces::Playground.create!(name: "Token Test Space", owner: @admin)
    @conversation = @space.conversations.create!(title: "Main")

    # Reset token counters
    @conversation.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
    @space.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
    @admin.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
  end

  test "records token usage to conversation" do
    usage = { prompt_tokens: 100, completion_tokens: 50 }

    TokenUsageRecorder.execute(conversation: @conversation, usage: usage)

    @conversation.reload
    assert_equal 100, @conversation.prompt_tokens_total
    assert_equal 50, @conversation.completion_tokens_total
  end

  test "records token usage to space" do
    usage = { prompt_tokens: 100, completion_tokens: 50 }

    TokenUsageRecorder.execute(conversation: @conversation, usage: usage)

    @space.reload
    assert_equal 100, @space.prompt_tokens_total
    assert_equal 50, @space.completion_tokens_total
  end

  test "records token usage to owner" do
    usage = { prompt_tokens: 100, completion_tokens: 50 }

    TokenUsageRecorder.execute(conversation: @conversation, usage: usage)

    @admin.reload
    assert_equal 100, @admin.prompt_tokens_total
    assert_equal 50, @admin.completion_tokens_total
  end

  test "accumulates multiple usages" do
    TokenUsageRecorder.execute(conversation: @conversation, usage: { prompt_tokens: 100, completion_tokens: 50 })
    TokenUsageRecorder.execute(conversation: @conversation, usage: { prompt_tokens: 200, completion_tokens: 100 })

    @conversation.reload
    assert_equal 300, @conversation.prompt_tokens_total
    assert_equal 150, @conversation.completion_tokens_total
  end

  test "handles nil usage gracefully" do
    # Should not raise an error
    TokenUsageRecorder.execute(conversation: @conversation, usage: nil)

    @conversation.reload
    assert_equal 0, @conversation.prompt_tokens_total
    assert_equal 0, @conversation.completion_tokens_total
  end

  test "handles empty usage gracefully" do
    TokenUsageRecorder.execute(conversation: @conversation, usage: {})

    @conversation.reload
    assert_equal 0, @conversation.prompt_tokens_total
    assert_equal 0, @conversation.completion_tokens_total
  end

  test "handles zero tokens gracefully" do
    TokenUsageRecorder.execute(conversation: @conversation, usage: { prompt_tokens: 0, completion_tokens: 0 })

    @conversation.reload
    assert_equal 0, @conversation.prompt_tokens_total
    assert_equal 0, @conversation.completion_tokens_total
  end

  test "handles missing conversation gracefully" do
    # Should not raise an error
    assert_nothing_raised do
      TokenUsageRecorder.execute(conversation: nil, usage: { prompt_tokens: 100, completion_tokens: 50 })
    end
  end

  test "handles string token values" do
    usage = { prompt_tokens: "100", completion_tokens: "50" }

    TokenUsageRecorder.execute(conversation: @conversation, usage: usage)

    @conversation.reload
    assert_equal 100, @conversation.prompt_tokens_total
    assert_equal 50, @conversation.completion_tokens_total
  end
end
