# frozen_string_literal: true

# Records LLM token usage to Conversation, Space, and User statistics.
#
# Uses atomic SQL updates to avoid race conditions in concurrent environments.
# User is always the Space owner - in group chats, all token consumption is
# attributed to the room owner for future billing purposes.
#
# @example Record usage from an LLM response
#   TokenUsageRecorder.call(
#     conversation: conversation,
#     usage: { prompt_tokens: 100, completion_tokens: 50 }
#   )
#
class TokenUsageRecorder
  # Record token usage to relevant records.
  #
  # @param conversation [Conversation] the conversation context
  # @param usage [Hash] token usage data with :prompt_tokens and :completion_tokens
  def self.call(conversation:, usage:)
    new(conversation: conversation, usage: usage).call
  end

  def initialize(conversation:, usage:)
    @conversation = conversation
    @usage = usage || {}
  end

  def call
    return unless valid_usage?

    increment_conversation!
    increment_space!
    increment_owner!
  rescue StandardError => e
    # Log but don't fail - token stats are not critical
    Rails.logger.warn "[TokenUsageRecorder] Failed to increment token stats: #{e.class}: #{e.message}"
  end

  private

  attr_reader :conversation, :usage

  def valid_usage?
    prompt_tokens.positive? || completion_tokens.positive?
  end

  def prompt_tokens
    @prompt_tokens ||= usage[:prompt_tokens].to_i
  end

  def completion_tokens
    @completion_tokens ||= usage[:completion_tokens].to_i
  end

  def increment_sql
    @increment_sql ||= "prompt_tokens_total = prompt_tokens_total + #{prompt_tokens}, " \
                       "completion_tokens_total = completion_tokens_total + #{completion_tokens}"
  end

  def increment_conversation!
    return unless conversation

    Conversation.where(id: conversation.id).update_all(increment_sql)
  end

  def increment_space!
    return unless conversation&.space_id

    Space.where(id: conversation.space_id).update_all(increment_sql)
  end

  def increment_owner!
    return unless conversation&.space&.owner_id

    User.where(id: conversation.space.owner_id).update_all(increment_sql)
  end
end
