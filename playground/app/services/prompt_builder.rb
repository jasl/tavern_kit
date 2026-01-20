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

  attr_reader :conversation, :space, :user_message, :speaker, :preset, :greeting_index, :history_scope, :generation_type

  # Initialize the prompt builder.
  #
  # @param conversation [Conversation] the conversation timeline
  # @param user_message [String, nil] optional new user message to include
  # @param speaker [Participant, nil] the AI character (or Auto user) that should respond
  # @param preset [TavernKit::Preset, nil] optional preset configuration
  # @param greeting_index [Integer, nil] greeting index for first message
  # @param history_scope [ActiveRecord::Relation, nil] custom scope for chat history
  #   (e.g., for regenerate: conversation.messages.ordered.with_participant.before_cursor(target))
  #   If nil, uses conversation.messages.ordered.with_participant
  # @param card_handling_mode [String, nil] optional override for Space#card_handling_mode ("swap", "append", "append_disabled")
  # @param generation_type [Symbol, String, Integer, nil] prompt trigger type (normal/continue/impersonate/swipe/regenerate/quiet)
  def initialize(conversation, user_message: nil, speaker: nil, preset: nil, greeting_index: nil, history_scope: nil, card_handling_mode: nil, generation_type: nil)
    @conversation = conversation
    @space = conversation.space
    @user_message = user_message
    @speaker = speaker || conversation.ai_respondable_participants.by_position.first
    @preset = preset
    @greeting_index = greeting_index
    @history_scope = history_scope
    @card_handling_mode_override = card_handling_mode.to_s.presence
    @generation_type = generation_type
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
    plan.to_messages(dialect: dialect, squash_system_messages: squash)
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
    return @group_chat if instance_variable_defined?(:@group_chat)

    @group_chat = conversation.group?
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
      generation_type: effective_generation_type,
      group: group_context,
      lore_books: lore_books,
      lore_engine: effective_lore_engine,
      injection_registry: injection_registry,
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

    membership = prompt_character_membership || @speaker
    ::PromptBuilding::ParticipantAdapter.to_participant(membership)
  end

  # Determine which SpaceMembership should provide the TavernKit character card.
  #
  # - AI character speaker: use the speaker directly.
  # - Human with character: use last AI speaker, first AI character, or speaker's character.
  # - Pure human (no character): use last AI speaker or first AI character.
  #   Pure humans have no character card, so we must use an AI character from the space.
  #
  # @return [SpaceMembership, nil]
  def prompt_character_membership
    return @prompt_character_membership if instance_variable_defined?(:@prompt_character_membership)

    @prompt_character_membership =
      if @speaker&.user?
        # Human member (Auto or suggestions) - need to determine character card source
        last_ai = conversation.last_assistant_message&.space_membership
        if last_ai&.ai_character?
          last_ai
        else
          # For human with character, can fall back to speaker's character
          # For pure human, must use an AI character from space
          first_ai = space.space_memberships.active.ai_characters.by_position.first
          @speaker&.character? ? (first_ai || @speaker) : first_ai
        end
      else
        @speaker
      end
  end

  def effective_character_participant
    @effective_character_participant ||=
      ::PromptBuilding::CharacterParticipantBuilder
        .new(
          space: space,
          current_character_membership: prompt_character_membership,
          participant: character_participant,
          group_chat: group_chat?,
          card_handling_mode_override: @card_handling_mode_override
        )
        .call
  end

  # Get the user participant for TavernKit.
  #
  # @return [TavernKit::User]
  def user_participant
    @user_participant ||= ::PromptBuilding::UserParticipantResolver.new(space: space, speaker: @speaker).call
  end

  # Check if the speaker is a human in Auto mode.
  # This includes:
  # - Human with persona character (user writing through a character)
  # - Pure human with custom persona (user with no character but has persona)
  #
  # @return [Boolean]
  def speaker_is_human_auto?
    @speaker&.user? && @speaker&.auto_enabled?
  end

  def effective_generation_type
    @effective_generation_type ||= begin
      default = speaker_is_human_auto? ? :impersonate : :normal
      ::TavernKit::Coerce.generation_type(@generation_type, default: default)
    end
  end

  # Get the effective preset configuration.
  #
  # @return [TavernKit::Preset]
  def effective_preset
    @effective_preset ||=
      ::PromptBuilding::PresetResolver
        .new(
          conversation: conversation,
          space: space,
          speaker: speaker,
          preset: @preset,
          default_max_context_tokens: DEFAULT_MAX_CONTEXT_TOKENS,
          default_max_response_tokens: DEFAULT_MAX_RESPONSE_TOKENS
        )
        .call
  end

  def effective_lore_engine
    return @effective_lore_engine if instance_variable_defined?(:@effective_lore_engine)

    @effective_lore_engine = ::PromptBuilding::LoreEngineBuilder.new(space: space).call
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
    relation = relation.included_in_prompt

    # Preload participant associations to avoid N+1 when converting to TavernKit messages.
    relation = relation.with_participant if relation.respond_to?(:with_participant)

    # Ensure chronological ordering for prompt building.
    relation = relation.reorder(seq: :asc, id: :asc)

    # Enforce default windowing only when the scope has no explicit limit.
    # Optimization: Use ID-based subquery instead of except(:includes) + re-preloading
    # to avoid stripping and re-applying associations.
    if relation.respond_to?(:limit_value) && relation.limit_value.nil?
      # First, get the IDs of the last N messages efficiently
      message_ids = relation
        .except(:includes, :preload, :eager_load)
        .reorder(seq: :desc, id: :desc)
        .limit(DEFAULT_HISTORY_WINDOW_MESSAGES)
        .pluck(:id)

      # Then fetch those messages with proper preloading in chronological order
      relation = ::Message
        .where(id: message_ids)
        .with_participant
        .reorder(seq: :asc, id: :asc)
    end

    ::PromptBuilding::MessageHistory.new(
      relation
    )
  end

  # Build the group context for group chats.
  #
  # @return [TavernKit::GroupContext, nil]
  def group_context
    return nil unless group_chat?

    @group_context ||= ::PromptBuilding::GroupContextBuilder.new(space: space, current_character_membership: prompt_character_membership).call
  end

  # Collect lore books from:
  # 0. Conversation lorebooks attached to the chat (ST: "Chat Lore")
  # 1. Global lorebooks attached to the space (via SpaceLorebook)
  # 2. Character-embedded lorebooks from all characters in the space
  # 3. Character-linked lorebooks (name-based soft links: data.extensions.world/extra_worlds)
  #
  # The insertion strategy (sorted_evenly, character_lore_first, global_lore_first)
  # is controlled by the preset and determines how these are ordered.
  #
  # @return [Array<TavernKit::Lore::Book>]
  def lore_books
    @lore_books ||= ::PromptBuilding::LoreBooksResolver.new(space: space, conversation: conversation).call
  end

  def injection_registry
    return @injection_registry if instance_variable_defined?(:@injection_registry)

    @injection_registry =
      ::PromptBuilding::InjectionRegistryBuilder
        .new(
          space: space,
          current_character_membership: prompt_character_membership,
          user: user_participant,
          history: chat_history,
          preset: effective_preset,
          group: group_context,
          user_message: user_message,
          generation_type: effective_generation_type,
          macro_vars: build_macro_vars,
          card_handling_mode_override: @card_handling_mode_override
        )
        .call
  end

  # Validate the conversation has required data for prompt building.
  #
  # We need a character card source. This can come from:
  # 1. An AI character in the space
  # 2. A human speaker with an associated character (persona character)
  # 3. The last AI assistant message's speaker (for pure human Auto)
  #
  # Pure human Auto (no character) without any AI characters AND no previous
  # AI messages cannot work because there's no character card to build the prompt.
  #
  # @raise [PromptBuilderError] if no character card source is available
  def validate_conversation!
    # AI characters in space can provide character card
    return if space.space_memberships.active.ai_characters.any?

    # Human with associated character can provide character card
    return if @speaker&.user? && @speaker&.character_id.present?

    # Pure human auto can use last AI speaker's character card
    if @speaker&.user? && @speaker&.auto_enabled?
      last_ai = conversation.last_assistant_message&.space_membership
      return if last_ai&.ai_character?
    end

    raise PromptBuilderError, "Space has no AI characters and no character card source available"
  end

  # Error class for prompt builder failures.
  class PromptBuilderError < StandardError; end
end
