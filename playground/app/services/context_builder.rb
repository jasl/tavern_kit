# frozen_string_literal: true

# ContextBuilder builds a deterministic prompt context for LLM calls.
#
# This is a thin wrapper over PromptBuilder (TavernKit), keeping a stable API for:
# - history cutoffs (before/through cursor messages)
# - explicit card handling mode overrides used by regenerate/preview flows
class ContextBuilder
  attr_reader :last_prompt_builder

  def initialize(conversation, speaker:)
    @conversation = conversation
    @space = conversation.space
    @speaker = speaker
    @last_prompt_builder = nil
  end

  # Build prompt messages.
  #
  # Cutoffs:
  # - before_message: excludes that message (used for regenerate)
  # - through_message: includes that message (used for branch/cursor previews)
  def build(before_message: nil, through_message: nil, card_mode: nil, generation_type: nil)
    raise ArgumentError, "before_message and through_message are mutually exclusive" if before_message && through_message

    history_scope = build_history_scope(before_message: before_message, through_message: through_message)
    @last_prompt_builder = PromptBuilder.new(
      conversation,
      speaker: speaker,
      history_scope: history_scope,
      card_handling_mode: normalize_card_handling_mode(card_mode),
      generation_type: generation_type
    )
    @last_prompt_builder.to_messages
  end

  # Get the lore result from the last build.
  # Returns nil if build has not been called or no lore was evaluated.
  #
  # @return [TavernKit::Lore::Result, nil]
  def lore_result
    @last_prompt_builder&.build&.lore_result
  end

  private

  attr_reader :conversation, :space, :speaker

  def build_history_scope(before_message:, through_message:)
    scope = conversation.messages.ordered.with_participant

    if before_message
      assert_same_conversation!(before_message)
      scope.where("seq < ?", before_message.seq)
    elsif through_message
      assert_same_conversation!(through_message)
      scope.where("seq <= ?", through_message.seq)
    else
      scope
    end
  end

  def assert_same_conversation!(message)
    return if message.conversation_id == conversation.id

    raise ArgumentError, "cursor message must belong to the conversation"
  end

  def normalize_card_handling_mode(card_mode)
    case card_mode.to_s
    when "", nil
      nil
    when "swap"
      "swap"
    when "join_include_non_participating"
      "append_disabled"
    when "join_exclude_non_participating"
      "append"
    else
      nil
    end
  end
end
