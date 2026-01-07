# frozen_string_literal: true

# Service for building LLM prompts using TavernKit.
#
# Converts Space/Conversation/Participant/Message models into TavernKit-compatible structures
# and builds prompts for chat completions.
#
# @example Basic usage
#   builder = PromptBuilder.new(conversation)
#   messages = builder.to_messages
#   # => [{role: "system", content: "..."}, {role: "user", content: "..."}, ...]
#
# @example With user message
#   builder = PromptBuilder.new(conversation, user_message: "Hello!")
#   plan = builder.build
#   messages = builder.to_messages
#
# @example With specific speaker
#   builder = PromptBuilder.new(conversation, speaker: character_participant)
#   messages = builder.to_messages
#
class PromptBuilder
  DEFAULT_MAX_CONTEXT_TOKENS = 8192
  DEFAULT_MAX_RESPONSE_TOKENS = 512
  DEFAULT_HISTORY_WINDOW_MESSAGES = 200

  attr_reader :conversation, :space, :user_message, :speaker, :preset, :greeting_index, :history_scope

  # Initialize the prompt builder.
  #
  # @param conversation [Conversation] the conversation timeline
  # @param user_message [String, nil] optional new user message to include
  # @param speaker [Participant, nil] the AI character (or copilot user) that should respond
  # @param preset [TavernKit::Preset, nil] optional preset configuration
  # @param greeting_index [Integer, nil] greeting index for first message
  # @param history_scope [ActiveRecord::Relation, nil] custom scope for chat history
  #   (e.g., for regenerate: conversation.messages.ordered.with_participant.before_cursor(target))
  #   If nil, uses conversation.messages.ordered.with_participant
  # @param card_handling_mode [String, nil] optional override for Space#card_handling_mode ("swap", "append", "append_disabled")
  def initialize(conversation, user_message: nil, speaker: nil, preset: nil, greeting_index: nil, history_scope: nil, card_handling_mode: nil)
    @conversation = conversation
    @space = conversation.space
    @user_message = user_message
    @speaker = speaker || conversation.ai_respondable_participants.by_position.first
    @preset = preset
    @greeting_index = greeting_index
    @history_scope = history_scope
    @card_handling_mode_override = card_handling_mode.to_s.presence
    @plan = nil
  end

  # Build the prompt plan.
  #
  # @return [TavernKit::Prompt::Plan]
  def build
    @plan ||= build_plan
  end

  # Build and convert to OpenAI-compatible messages.
  #
  # @param dialect [Symbol] output dialect (:openai, :anthropic, :text)
  # @return [Array<Hash>, Hash, String] messages in the specified format
  def to_messages(dialect: :openai)
    plan = build
    squash = effective_preset.squash_system_messages
    messages = plan.to_messages(dialect: dialect, squash_system_messages: squash)

    # For copilot mode (user with persona), we need special handling
    if speaker_is_user_with_persona? && messages.is_a?(Array)
      # Remove trailing empty user messages first
      while messages.last&.dig(:role) == "user" && messages.last&.dig(:content).to_s.strip.empty?
        messages.pop
      end

      # If the last message is from assistant, add a system prompt to guide
      # the LLM to generate a response as the user's persona character.
      # Without this, the LLM sees an assistant message at the end and
      # returns empty content thinking the conversation is complete.
      if messages.last&.dig(:role) == "assistant"
        persona_name = speaker&.character&.name || "the user's character"
        messages << {
          role: "system",
          content: "[Continue the roleplay. Write the next response as #{persona_name}. Stay in character and respond naturally to what was just said.]",
        }
      end
    end

    messages
  end

  # Get the resolved greeting (for new chats).
  #
  # @return [String, nil]
  def greeting
    build.greeting
  end

  # Check if this is a group chat.
  #
  # @return [Boolean]
  def group_chat?
    conversation.group?
  end

  private

  # Build the TavernKit prompt plan.
  #
  # @return [TavernKit::Prompt::Plan]
  def build_plan
    validate_conversation!

    ::TavernKit.build(
      character: effective_character_participant,
      user: user_participant,
      preset: effective_preset,
      history: chat_history,
      message: user_message,
      group: group_context,
      lore_books: lore_books,
      lore_engine: effective_lore_engine,
      greeting_index: greeting_index,
      macro_vars: build_macro_vars
    )
  end

  # Build macro variables including the variables store for timed effects.
  #
  # @return [Hash]
  def build_macro_vars
    {
      local_store: conversation.variables_store,
    }
  end

  # Get the character participant for TavernKit.
  #
  # @return [TavernKit::Character]
  # @raise [PromptBuilderError] if no speaker is set
  def character_participant
    raise PromptBuilderError, "No speaker selected for AI response" unless @speaker

    ::PromptBuilding::ParticipantAdapter.to_participant(@speaker)
  end

  def effective_character_participant
    ::PromptBuilding::CharacterParticipantBuilder
      .new(
        space: space,
        speaker: speaker,
        participant: character_participant,
        group_chat: group_chat?,
        card_handling_mode_override: @card_handling_mode_override
      )
      .call
  end

  # Get the user participant for TavernKit.
  #
  # When the speaker is a user participant with a persona character (copilot mode),
  # the "user" in the conversation is actually the AI character, not the speaker.
  # This allows the prompt to correctly frame the conversation.
  #
  # @return [TavernKit::User]
  def user_participant
    ::PromptBuilding::UserParticipantResolver.new(space: space, speaker: @speaker).call
  end

  # Check if the speaker is a user participant with a persona character.
  # This indicates "copilot mode" where the user is roleplaying as a character.
  #
  # @return [Boolean]
  def speaker_is_user_with_persona?
    @speaker&.user? && @speaker&.character?
  end

  # Get the effective preset configuration.
  #
  # @return [TavernKit::Preset]
  def effective_preset
    ::PromptBuilding::PresetResolver.new(
      conversation: conversation,
      space: space,
      speaker: speaker,
      preset: @preset,
      default_max_context_tokens: DEFAULT_MAX_CONTEXT_TOKENS,
      default_max_response_tokens: DEFAULT_MAX_RESPONSE_TOKENS
    ).call
  end

  def effective_lore_engine
    ::PromptBuilding::LoreEngineBuilder.new(space: space).call
  end
  # Build the chat history from conversation messages.
  #
  # @return [PromptBuilding::MessageHistory]
  def chat_history
    # Prompt history is a TavernKit-facing *data source* (MessageHistory) fed from a
    # windowed ActiveRecord relation.
    #
    # - Default: last N messages (message-count window) to keep DB load predictable.
    # - If `history_scope` has an explicit limit, we respect it.
    # - Messages excluded from prompt context are filtered here (before windowing).
    relation = @history_scope || conversation.messages.ordered

    # Only include messages that should be sent to the LLM.
    # This MUST happen before windowing so the window counts only included messages.
    relation = relation.where(excluded_from_prompt: false)

    # Preload participant associations to avoid N+1 when converting to TavernKit messages.
    relation = relation.with_participant if relation.respond_to?(:with_participant)

    # Ensure chronological ordering for prompt building.
    relation = relation.reorder(seq: :asc, id: :asc)

    # Enforce default windowing only when the scope has no explicit limit.
    if relation.respond_to?(:limit_value) && relation.limit_value.nil?
      window = relation
        .except(:includes, :preload, :eager_load)
        .reorder(seq: :desc, id: :desc)
        .limit(DEFAULT_HISTORY_WINDOW_MESSAGES)

      relation = ::Message
        .from(window, :messages)
        .with_participant
        .reorder(seq: :asc, id: :asc)
    end

    # For copilot mode (user with persona as speaker), we need to flip roles
    # so messages from the speaker's character are "assistant" and others are "user"
    ::PromptBuilding::MessageHistory.new(
      relation,
      copilot_speaker: speaker_is_user_with_persona? ? @speaker : nil
    )
  end

  # Build the group context for group chats.
  #
  # @return [TavernKit::GroupContext, nil]
  def group_context
    return nil unless group_chat?

    ::PromptBuilding::GroupContextBuilder.new(space: space, speaker: @speaker).call
  end

  # Collect lore books from:
  # 1. Global lorebooks attached to the space (via SpaceLorebook)
  # 2. Character-embedded lorebooks from all characters in the space
  # 3. Character-linked lorebooks (via CharacterLorebook)
  #
  # The insertion strategy (sorted_evenly, character_lore_first, global_lore_first)
  # is controlled by the preset and determines how these are ordered.
  #
  # @return [Array<TavernKit::Lore::Book>]
  def lore_books
    ::PromptBuilding::LoreBooksResolver.new(space: space).call
  end

  # Validate the conversation has required data.
  #
  # @raise [PromptBuilderError] if conversation is invalid
  def validate_conversation!
    if space.space_memberships.participating.ai_characters.empty? && !speaker_is_user_with_persona?
      raise PromptBuilderError, "Space has no AI characters"
    end
  end

  # Error class for prompt builder failures.
  class PromptBuilderError < StandardError; end
end
