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

    @speaker.to_participant
  end

  def effective_character_participant
    participant = character_participant

    scenario_override = (space.settings || {})["scenario_override"].presence
    return participant unless participant.is_a?(::TavernKit::Character)

    overrides = {}

    card_handling_mode = normalized_card_handling_mode

    if group_chat? && %w[append append_disabled].include?(card_handling_mode)
      overrides.merge!(
        joined_character_overrides(
          include_non_participating: card_handling_mode == "append_disabled",
          scenario_override: scenario_override
        )
      )
    else
      overrides[:scenario] = scenario_override.to_s if scenario_override
    end

    if participant.data.character_book.is_a?(Hash)
      overridden_book = apply_world_info_overrides_to_book_hash(participant.data.character_book)
      overrides[:character_book] = overridden_book if overridden_book
    end

    return participant if overrides.empty?

    overridden_data = participant.data.with(**overrides)

    ::TavernKit::Character.new(
      data: overridden_data,
      source_version: participant.source_version,
      raw: participant.raw
    )
  end

  def normalized_card_handling_mode
    mode = @card_handling_mode_override
    return mode if mode.present?
    return "swap" unless space.respond_to?(:card_handling_mode)

    mode = space.card_handling_mode.to_s
    mode.presence || "swap"
  end

  def joined_character_overrides(include_non_participating:, scenario_override:)
    join_prefix = (space.settings || {})["join_prefix"].to_s
    join_suffix = (space.settings || {})["join_suffix"].to_s

    participants = space.space_memberships.active.ai_characters.by_position.includes(:character).to_a

    if speaker&.character? && participants.none? { |p| p.id == speaker.id }
      participants << speaker
    end

    unless include_non_participating
      participants.select! { |p| p.participation_active? || (speaker && p.id == speaker.id) }
    end

    description = join_character_field(
      participants,
      field_name: "description",
      join_prefix: join_prefix,
      join_suffix: join_suffix
    ) { |char| char.data.description }

    scenario = join_character_field(
      participants,
      field_name: "scenario",
      join_prefix: join_prefix,
      join_suffix: join_suffix
    ) do |char|
      scenario_override.present? ? scenario_override.to_s : char.data.scenario
    end

    personality = join_character_field(
      participants,
      field_name: "personality",
      join_prefix: join_prefix,
      join_suffix: join_suffix
    ) { |char| char.data.personality }

    mes_example = join_character_field(
      participants,
      field_name: "mes_example",
      join_prefix: join_prefix,
      join_suffix: join_suffix
    ) { |char| char.data.mes_example }

    creator_notes = join_character_field(
      participants,
      field_name: "creator_notes",
      join_prefix: join_prefix,
      join_suffix: join_suffix
    ) { |char| char.data.creator_notes }

    depth_prompt = join_character_depth_prompt(
      participants,
      join_prefix: join_prefix,
      join_suffix: join_suffix
    )

    overrides = {
      description: description,
      scenario: scenario,
      personality: personality,
      mes_example: mes_example,
      creator_notes: creator_notes,
    }.compact

    if depth_prompt.present?
      extensions = (character_participant.data.extensions || {}).deep_dup
      extensions = extensions.deep_stringify_keys
      depth_hash = extensions["depth_prompt"].is_a?(Hash) ? extensions["depth_prompt"].deep_dup : {}
      depth_hash = depth_hash.deep_stringify_keys
      depth_hash["prompt"] = depth_prompt
      depth_hash["depth"] ||= 4
      depth_hash["role"] ||= "system"
      extensions["depth_prompt"] = depth_hash
      overrides[:extensions] = extensions
    end

    overrides
  end

  def join_character_depth_prompt(participants, join_prefix:, join_suffix:)
    join_character_field(
      participants,
      field_name: "depth_prompt",
      join_prefix: join_prefix,
      join_suffix: join_suffix
    ) do |char|
      extensions = char.data.extensions
      next nil unless extensions.is_a?(Hash)

      depth_hash = extensions["depth_prompt"] || extensions[:depth_prompt]
      next nil unless depth_hash.is_a?(Hash)

      depth_hash["prompt"] || depth_hash[:prompt]
    end
  end

  def join_character_field(participants, field_name:, join_prefix:, join_suffix:)
    segments =
      participants.filter_map do |participant_record|
        participant = participant_record.to_participant
        next unless participant.is_a?(::TavernKit::Character)

        char_name = participant.name.to_s.presence || participant_record.display_name.to_s
        raw = yield(participant)
        next if raw.to_s.strip.empty?

        prefix = apply_join_template(join_prefix, character_name: char_name, field_name: field_name)
        suffix = apply_join_template(join_suffix, character_name: char_name, field_name: field_name)
        body = raw.to_s.gsub(/\{\{char\}\}/i, char_name)

        +"#{prefix}#{body}#{suffix}"
      end

    return nil if segments.empty?

    segments.join("\n")
  end

  def apply_join_template(template, character_name:, field_name:)
    template
      .to_s
      .gsub(/\{\{char\}\}/i, character_name.to_s)
      .gsub(/<fieldname>(?=>)/i, "#{field_name}>")
      .gsub(/<fieldname>/i, field_name.to_s)
  end

  # Get the user participant for TavernKit.
  #
  # When the speaker is a user participant with a persona character (copilot mode),
  # the "user" in the conversation is actually the AI character, not the speaker.
  # This allows the prompt to correctly frame the conversation.
  #
  # @return [TavernKit::User]
  def user_participant
    # For copilot mode: speaker is user participant with a persona character
    # In this case, the "user" should be the AI character (the other party)
    if speaker_is_user_with_persona?
      # Find the first AI character participant as the "user" (other party)
      ai_membership = space.space_memberships.participating.ai_characters.by_position.first
      if ai_membership
        return ::TavernKit::User.new(
          name: ai_membership.display_name,
          persona: ai_membership.character&.personality
        )
      end
    end

    # Normal case: find the user participant
    user_participant =
      space.space_memberships.active.find { |m| m.user? && !m.copilot_full? } ||
      space.space_memberships.active.find(&:user?)

    if user_participant
      user_participant.to_user_participant
    else
      # Fallback for rooms without direct user participation
      ::TavernKit::User.new(name: "User", persona: nil)
    end
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
    base = @preset || ::TavernKit::Preset.new

    overrides = {}
    space_settings = space.settings || {}
    preset_settings = space_settings["preset"]

    if preset_settings.is_a?(Hash)
      overrides[:main_prompt] = preset_settings["main_prompt"].to_s if preset_settings.key?("main_prompt")
      if preset_settings.key?("post_history_instructions")
        overrides[:post_history_instructions] = preset_settings["post_history_instructions"].to_s
      end
      overrides[:new_chat_prompt] = preset_settings["new_chat_prompt"].to_s if preset_settings.key?("new_chat_prompt")
      overrides[:new_group_chat_prompt] = preset_settings["new_group_chat_prompt"].to_s if preset_settings.key?("new_group_chat_prompt")
      overrides[:new_example_chat] = preset_settings["new_example_chat"].to_s if preset_settings.key?("new_example_chat")
      overrides[:group_nudge_prompt] = preset_settings["group_nudge_prompt"].to_s if preset_settings.key?("group_nudge_prompt")
      overrides[:continue_nudge_prompt] = preset_settings["continue_nudge_prompt"].to_s if preset_settings.key?("continue_nudge_prompt")
      overrides[:replace_empty_message] = preset_settings["replace_empty_message"].to_s if preset_settings.key?("replace_empty_message")

      if preset_settings.key?("continue_prefill")
        overrides[:continue_prefill] = preset_settings["continue_prefill"] == true
      end

      overrides[:continue_postfix] = preset_settings["continue_postfix"].to_s if preset_settings.key?("continue_postfix")

      if preset_settings.key?("prefer_char_prompt")
        overrides[:prefer_char_prompt] = preset_settings["prefer_char_prompt"] != false
      end

      if preset_settings.key?("prefer_char_instructions")
        overrides[:prefer_char_instructions] = preset_settings["prefer_char_instructions"] != false
      end

      overrides[:squash_system_messages] = preset_settings["squash_system_messages"] == true if preset_settings.key?("squash_system_messages")

      if preset_settings.key?("examples_behavior")
        overrides[:examples_behavior] = ::TavernKit::Coerce.examples_behavior(preset_settings["examples_behavior"])
      end

      if preset_settings.key?("message_token_overhead")
        overrides[:message_token_overhead] = normalize_non_negative_integer(preset_settings["message_token_overhead"])
      end

      overrides[:enhance_definitions] = preset_settings["enhance_definitions"].to_s if preset_settings.key?("enhance_definitions")
      overrides[:auxiliary_prompt] = preset_settings["auxiliary_prompt"].to_s if preset_settings.key?("auxiliary_prompt")

      # Apply Author's Note with 4-layer priority chain
      an_overrides = resolve_authors_note_settings(preset_settings)
      overrides.merge!(an_overrides)

      overrides[:wi_format] = preset_settings["wi_format"].to_s if preset_settings.key?("wi_format")
      overrides[:scenario_format] = preset_settings["scenario_format"].to_s if preset_settings.key?("scenario_format")
      overrides[:personality_format] = preset_settings["personality_format"].to_s if preset_settings.key?("personality_format")
    end

    generation = speaker_generation_settings
    max_context_tokens = normalize_positive_integer(generation["max_context_tokens"])
    max_response_tokens = normalize_positive_integer(generation["max_response_tokens"])

    overrides[:context_window_tokens] = max_context_tokens if max_context_tokens
    overrides[:reserved_response_tokens] = max_response_tokens if max_response_tokens

    if space_settings.key?("world_info_depth")
      overrides[:world_info_depth] = normalize_non_negative_integer(space_settings["world_info_depth"])
    end

    if space_settings.key?("world_info_include_names")
      overrides[:world_info_include_names] = space_settings["world_info_include_names"] != false
    end

    if space_settings.key?("world_info_min_activations")
      overrides[:world_info_min_activations] = normalize_non_negative_integer(space_settings["world_info_min_activations"])
    end

    if space_settings.key?("world_info_min_activations_depth_max")
      overrides[:world_info_min_activations_depth_max] = normalize_non_negative_integer(space_settings["world_info_min_activations_depth_max"])
    end

    if space_settings.key?("world_info_use_group_scoring")
      overrides[:world_info_use_group_scoring] = space_settings["world_info_use_group_scoring"] == true
    end

    if space_settings.key?("world_info_insertion_strategy")
      overrides[:character_lore_insertion_strategy] = ::TavernKit::Coerce.insertion_strategy(space_settings["world_info_insertion_strategy"])
    end

    percent = normalize_non_negative_integer(space_settings["world_info_budget"]) if space_settings.key?("world_info_budget")
    if percent && percent.positive?
      context_window = overrides[:context_window_tokens] || base.context_window_tokens
      reserved = overrides[:reserved_response_tokens] || base.reserved_response_tokens
      overrides[:world_info_budget] = percent_budget_to_tokens(percent, context_window_tokens: context_window, reserved_response_tokens: reserved)
    end

    if space_settings.key?("world_info_budget_cap")
      overrides[:world_info_budget_cap] = normalize_non_negative_integer(space_settings["world_info_budget_cap"])
    end

    overrides.compact!

    overrides.any? ? base.with(**overrides) : base
  end

  def effective_lore_engine
    settings = space.settings || {}

    has_custom =
      settings.key?("world_info_match_whole_words") ||
      settings.key?("world_info_case_sensitive") ||
      settings.key?("world_info_max_recursion_steps")

    return nil unless has_custom

    match_whole_words = settings.fetch("world_info_match_whole_words", true) != false
    case_sensitive = settings["world_info_case_sensitive"] == true

    max_steps = normalize_non_negative_integer(settings["world_info_max_recursion_steps"])
    max_steps = 3 if max_steps.nil?

    ::TavernKit::Lore::Engine.new(
      token_estimator: ::TavernKit::TokenEstimator.default,
      match_whole_words: match_whole_words,
      case_sensitive: case_sensitive,
      max_recursion_steps: max_steps
    )
  end

  def apply_world_info_overrides_to_book_hash(book_hash)
    return nil unless book_hash.is_a?(Hash)

    recursive =
      if (space.settings || {}).key?("world_info_recursive")
        (space.settings || {})["world_info_recursive"] == true
      else
        true
      end

    dup = book_hash.deep_dup
    dup["recursiveScanning"] = recursive
    dup["recursive_scanning"] = recursive
    dup
  end

  def speaker_generation_settings
    return {} unless speaker

    llm = speaker.llm_settings
    provider_id = speaker.provider_identification
    return {} if provider_id.blank?

    defaults = {
      "max_context_tokens" => DEFAULT_MAX_CONTEXT_TOKENS,
      "max_response_tokens" => DEFAULT_MAX_RESPONSE_TOKENS,
    }

    provided = llm.dig("providers", provider_id, "generation") || {}
    defaults.merge(provided)
  end

  def normalize_positive_integer(value)
    n = Integer(value)
    n.positive? ? n : nil
  rescue ArgumentError, TypeError
    nil
  end

  def normalize_non_negative_integer(value)
    return nil if value.nil?

    n = Integer(value)
    n.negative? ? 0 : n
  rescue ArgumentError, TypeError
    nil
  end

  def percent_budget_to_tokens(percent, context_window_tokens:, reserved_response_tokens: 0)
    return nil unless context_window_tokens

    percent = percent.to_i.clamp(0, 100)
    available = [context_window_tokens.to_i - reserved_response_tokens.to_i, 0].max
    ((available * percent) / 100.0).floor
  end

  # Resolve Author's Note settings with 4-layer priority chain.
  #
  # Priority (highest to lowest):
  # 1. Conversation.authors_note
  # 2. SpaceMembership.settings.authors_note
  # 3. Character.authors_note_settings
  # 4. Space.settings.preset.authors_note
  #
  # @param preset_settings [Hash] the Space-level preset settings
  # @return [Hash] overrides hash with resolved AN settings
  def resolve_authors_note_settings(preset_settings)
    overrides = {}

    # Layer 1: Conversation-level (highest priority)
    if conversation.authors_note.present?
      overrides[:authors_note] = conversation.authors_note
      # Use Conversation-level settings if set, otherwise fallback to preset
      apply_conversation_authors_note_metadata(overrides, preset_settings)
      return overrides
    end

    # Layer 2 & 3: SpaceMembership and Character level
    if speaker&.character?
      sm_an = speaker.authors_note_settings["authors_note"].presence
      char_an = speaker.character&.authors_note if speaker.use_character_authors_note?

      if sm_an.present? || char_an.present?
        # Determine the combined AN content based on character_authors_note_position
        combined_an = combine_character_authors_note(
          space_an: preset_settings["authors_note"].to_s.presence,
          sm_an: sm_an,
          char_an: char_an,
          position: speaker.character_authors_note_position
        )

        if combined_an.present?
          overrides[:authors_note] = combined_an

          # Apply metadata from SM > Character > Space chain
          apply_authors_note_metadata_from_speaker(overrides, preset_settings)
          return overrides
        end
      end
    end

    # Layer 4: Space preset level (fallback)
    if preset_settings.key?("authors_note")
      overrides[:authors_note] = preset_settings["authors_note"].to_s
    end
    apply_authors_note_metadata(overrides, preset_settings)

    overrides
  end

  # Combine character AN with space AN based on position mode.
  #
  # @param space_an [String, nil] space-level AN
  # @param sm_an [String, nil] SpaceMembership AN override
  # @param char_an [String, nil] character AN
  # @param position [String] "replace", "before", or "after"
  # @return [String, nil]
  def combine_character_authors_note(space_an:, sm_an:, char_an:, position:)
    # SM override takes priority over character
    effective_char_an = sm_an.presence || char_an

    return nil if effective_char_an.blank?

    case position
    when "before"
      [effective_char_an, space_an].compact.join("\n")
    when "after"
      [space_an, effective_char_an].compact.join("\n")
    else # "replace"
      effective_char_an
    end
  end

  # Apply AN metadata from preset settings (position, depth, role, frequency).
  #
  # @param overrides [Hash] the overrides hash to modify
  # @param preset_settings [Hash] the Space-level preset settings
  def apply_authors_note_metadata(overrides, preset_settings)
    if preset_settings.key?("authors_note_frequency")
      overrides[:authors_note_frequency] = normalize_non_negative_integer(preset_settings["authors_note_frequency"])
    end

    if preset_settings.key?("authors_note_position")
      overrides[:authors_note_position] = ::TavernKit::Coerce.authors_note_position(preset_settings["authors_note_position"])
    end

    if preset_settings.key?("authors_note_depth")
      overrides[:authors_note_depth] = normalize_non_negative_integer(preset_settings["authors_note_depth"])
    end

    if preset_settings.key?("authors_note_role")
      overrides[:authors_note_role] = ::TavernKit::Coerce.role(preset_settings["authors_note_role"])
    end
  end

  # Apply AN metadata with Conversation > Space priority chain.
  # Used when Conversation has an authors_note set.
  #
  # @param overrides [Hash] the overrides hash to modify
  # @param preset_settings [Hash] the Space-level preset settings (fallback)
  def apply_conversation_authors_note_metadata(overrides, preset_settings)
    # Position: Conversation > Space
    position = conversation.authors_note_position.presence || preset_settings["authors_note_position"]
    overrides[:authors_note_position] = ::TavernKit::Coerce.authors_note_position(position) if position

    # Depth: Conversation > Space
    depth = conversation.authors_note_depth || preset_settings["authors_note_depth"]
    overrides[:authors_note_depth] = normalize_non_negative_integer(depth) if depth

    # Role: Conversation > Space
    role = conversation.authors_note_role.presence || preset_settings["authors_note_role"]
    overrides[:authors_note_role] = ::TavernKit::Coerce.role(role) if role

    # Frequency: Only from Space (Conversation doesn't have frequency)
    if preset_settings.key?("authors_note_frequency")
      overrides[:authors_note_frequency] = normalize_non_negative_integer(preset_settings["authors_note_frequency"])
    end
  end

  # Apply AN metadata with SM > Character > Space priority chain.
  #
  # @param overrides [Hash] the overrides hash to modify
  # @param preset_settings [Hash] the Space-level preset settings (fallback)
  def apply_authors_note_metadata_from_speaker(overrides, preset_settings)
    return apply_authors_note_metadata(overrides, preset_settings) unless speaker&.character?

    sm_settings = speaker.authors_note_settings
    char = speaker.character

    # Position: SM > Character > Space
    position = sm_settings["authors_note_position"].presence ||
               char&.authors_note_position ||
               preset_settings["authors_note_position"]
    overrides[:authors_note_position] = ::TavernKit::Coerce.authors_note_position(position) if position

    # Depth: SM > Character > Space
    depth = sm_settings["authors_note_depth"] ||
            char&.authors_note_depth ||
            preset_settings["authors_note_depth"]
    overrides[:authors_note_depth] = normalize_non_negative_integer(depth) if depth

    # Role: SM > Character > Space
    role = sm_settings["authors_note_role"].presence ||
           char&.authors_note_role ||
           preset_settings["authors_note_role"]
    overrides[:authors_note_role] = ::TavernKit::Coerce.role(role) if role

    # Frequency: SM > Character > Space (only from preset for now)
    if preset_settings.key?("authors_note_frequency")
      overrides[:authors_note_frequency] = normalize_non_negative_integer(preset_settings["authors_note_frequency"])
    end
  end

  # Build the chat history from conversation messages.
  #
  # @return [PromptBuilder::ActiveRecordChatHistory]
  def chat_history
    # Use custom scope if provided, otherwise default to all messages
    # Custom scope is used for regenerate (messages before target)
    relation = @history_scope || conversation.messages.ordered.with_participant

    # For copilot mode (user with persona as speaker), we need to flip roles
    # so messages from the speaker's character are "assistant" and others are "user"
    ActiveRecordChatHistory.new(
      relation,
      copilot_speaker: speaker_is_user_with_persona? ? @speaker : nil
    )
  end

  # Build the group context for group chats.
  #
  # @return [TavernKit::GroupContext, nil]
  def group_context
    return nil unless group_chat?

    character_memberships = space.space_memberships.active.ai_characters.by_position
    # Active participants (participation: active)
    member_names = character_memberships.select(&:participation_active?).map(&:display_name)
    # Non-participating members (muted/observer) - mapped to "muted" for TavernKit compatibility
    non_participating_names = character_memberships.reject(&:participation_active?).map(&:display_name)
    current_character = @speaker&.display_name

    ::TavernKit::GroupContext.new(
      members: member_names,
      muted: non_participating_names,
      current_character: current_character
    )
  end

  # Collect lore books from:
  # 1. Global lorebooks attached to the space (via SpaceLorebook)
  # 2. Character-embedded lorebooks from all characters in the space
  #
  # The insertion strategy (sorted_evenly, character_lore_first, global_lore_first)
  # is controlled by the preset and determines how these are ordered.
  #
  # @return [Array<TavernKit::Lore::Book>]
  def lore_books
    books = []

    # 1. Global lorebooks attached to the space
    space.space_lorebooks.enabled.by_priority.includes(:lorebook).each do |space_lorebook|
      lorebook = space_lorebook.lorebook
      book = lorebook.to_lore_book(source: :global)
      books << book if book.entries.any?
    end

    # 2. Character-embedded lorebooks
    space.space_memberships.active.ai_characters.includes(:character).find_each do |membership|
      character = membership.character
      next unless character&.character_book.present?

      effective_book_hash = apply_world_info_overrides_to_book_hash(character.character_book)
      next unless effective_book_hash

      book = ::TavernKit::Lore::Book.from_hash(effective_book_hash, source: :character)
      books << book
    end

    books
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

  # ActiveRecord-backed ChatHistory adapter.
  #
  # Wraps an ActiveRecord relation of Message records to implement
  # TavernKit's ChatHistory interface without loading all messages
  # into memory at once.
  #
  # @example Usage
  #   history = ActiveRecordChatHistory.new(conversation.messages.ordered)
  #   history.each { |msg| puts msg.content }
  #
  # @example Copilot mode (flip roles for user with persona)
  #   history = ActiveRecordChatHistory.new(conversation.messages.ordered, copilot_speaker: user_participant)
  #   # Messages from copilot_speaker's character become "assistant"
  #   # Messages from other characters become "user"
  #
  class ActiveRecordChatHistory < ::TavernKit::ChatHistory::Base
    # @param relation [ActiveRecord::Relation<Message>]
    # @param copilot_speaker [SpaceMembership, nil] if set, flip roles for copilot mode
    def initialize(relation, copilot_speaker: nil)
      @relation = relation
      @copilot_speaker = copilot_speaker
    end

    # Iterate over all messages as TavernKit::Prompt::Message objects.
    #
    # Note: We use `each` instead of `find_each` to preserve the ordering
    # from the relation (find_each ignores ORDER BY and orders by primary key).
    #
    # Messages marked as excluded_from_prompt are skipped (they remain visible
    # in the UI but are not sent to the LLM).
    #
    # @yield [TavernKit::Prompt::Message] each message
    # @return [Enumerator] if no block given
    def each(&block)
      return to_enum(:each) unless block

      @relation.each do |message|
        next if message.excluded_from_prompt?

        yield convert_message(message)
      end
    end

    # Get the number of messages.
    #
    # @return [Integer]
    def size
      # Keep `size` consistent with `each`, which skips messages that are excluded
      # from the prompt context.
      #
      # NOTE: We intentionally count *within* the relation's current window (including
      # any ORDER/LIMIT/OFFSET) and then filter out excluded rows, so `size` reflects
      # how many messages `each` will actually yield.
      if @relation.loaded?
        @relation.count { |message| !message.excluded_from_prompt? }
      else
        window = @relation
          .except(:includes, :preload, :eager_load)
          .reselect(:id, :excluded_from_prompt)

        ::Message
          .from(window, :windowed_messages)
          .where("windowed_messages.excluded_from_prompt = ?", false)
          .count
      end
    end

    # Append a message (not supported for ActiveRecord history).
    #
    # @param message [TavernKit::Prompt::Message]
    # @raise [NotImplementedError]
    def append(message)
      raise NotImplementedError, "ActiveRecordChatHistory is read-only. Use Message.create! to add messages."
    end

    # Clear all messages (not supported for ActiveRecord history).
    #
    # @raise [NotImplementedError]
    def clear
      raise NotImplementedError, "ActiveRecordChatHistory is read-only. Use conversation.messages.destroy_all to clear."
    end

    private

    # Convert an ActiveRecord Message to TavernKit::Prompt::Message.
    #
    # In copilot mode, roles are flipped:
    # - Messages from the copilot speaker's character become "assistant"
    # - Messages from other characters become "user"
    #
    # This ensures the prompt is built from the speaker's perspective.
    #
    # @param message [Message]
    # @return [TavernKit::Prompt::Message]
    def convert_message(message)
      role = determine_role(message)

      ::TavernKit::Prompt::Message.new(
        role: role,
        content: message.plain_text_content,
        name: message.sender_display_name,
        send_date: message.created_at&.to_i
      )
    end

    # Determine the role for a message, flipping if in copilot mode.
    #
    # @param message [Message]
    # @return [Symbol] :user or :assistant
    def determine_role(message)
      return message.role.to_sym unless @copilot_speaker

      # In copilot mode, flip roles based on who sent the message
      message_character_id = message.space_membership.character_id
      speaker_character_id = @copilot_speaker.character_id

      if message_character_id == speaker_character_id
        # Message is from the speaker's character (user with persona)
        # This should be "assistant" in the prompt
        :assistant
      else
        # Message is from other characters (AI characters)
        # This should be "user" in the prompt
        :user
      end
    end
  end
end
