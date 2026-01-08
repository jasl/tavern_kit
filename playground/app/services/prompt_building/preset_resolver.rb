# frozen_string_literal: true

module PromptBuilding
  class PresetResolver
    def initialize(conversation:, space:, speaker:, preset:, default_max_context_tokens:, default_max_response_tokens:)
      @conversation = conversation
      @space = space
      @speaker = speaker
      @preset = preset
      @default_max_context_tokens = default_max_context_tokens
      @default_max_response_tokens = default_max_response_tokens
    end

    # @return [TavernKit::Preset]
    def call
      base = @preset || ::TavernKit::Preset.new

      overrides = {}
      prompt_settings = @space.prompt_settings
      space_preset_settings = prompt_settings&.preset
      membership_preset_settings = speaker_preset_settings

      if space_preset_settings && (@preset.nil? || preset_settings_have_overrides?(space_preset_settings))
        apply_preset_settings_overrides!(overrides, space_preset_settings, only_non_defaults: false)
      end

      if membership_preset_settings && (@preset.nil? || preset_settings_have_overrides?(membership_preset_settings))
        apply_preset_settings_overrides!(overrides, membership_preset_settings, only_non_defaults: true)
      end

      overrides.merge!(
        ::PromptBuilding::AuthorsNoteResolver
          .new(conversation: @conversation, speaker: @speaker, preset_settings: space_preset_settings)
          .call
      )

      generation = speaker_generation_settings
      max_context_tokens = normalize_positive_integer(generation["max_context_tokens"])
      max_response_tokens = normalize_positive_integer(generation["max_response_tokens"])

      overrides[:context_window_tokens] = max_context_tokens if max_context_tokens
      overrides[:reserved_response_tokens] = max_response_tokens if max_response_tokens

      wi_settings = prompt_settings&.world_info
      if wi_settings
        overrides[:world_info_depth] = normalize_non_negative_integer(wi_settings.depth) if wi_settings.depth
        overrides[:world_info_include_names] = wi_settings.include_names != false
        overrides[:world_info_min_activations] = normalize_non_negative_integer(wi_settings.min_activations) if wi_settings.min_activations
        overrides[:world_info_min_activations_depth_max] = normalize_non_negative_integer(wi_settings.min_activations_depth_max) if wi_settings.min_activations_depth_max
        overrides[:world_info_use_group_scoring] = wi_settings.use_group_scoring == true
        overrides[:character_lore_insertion_strategy] = ::TavernKit::Coerce.insertion_strategy(wi_settings.insertion_strategy) if wi_settings.insertion_strategy.present?

        percent = normalize_non_negative_integer(wi_settings.budget_percent)
        if percent && percent.positive?
          context_window = overrides[:context_window_tokens] || base.context_window_tokens
          reserved = overrides[:reserved_response_tokens] || base.reserved_response_tokens
          overrides[:world_info_budget] = percent_budget_to_tokens(percent, context_window_tokens: context_window, reserved_response_tokens: reserved)
        end

        overrides[:world_info_budget_cap] = normalize_non_negative_integer(wi_settings.budget_cap_tokens) if wi_settings.budget_cap_tokens
      end

      overrides.compact!
      overrides.any? ? base.with(**overrides) : base
    end

    private

    def preset_settings_have_overrides?(preset_settings)
      tmp = {}
      apply_preset_settings_overrides!(tmp, preset_settings, only_non_defaults: true)
      tmp.any?
    end

    def speaker_preset_settings
      return nil unless @speaker

      @speaker.settings&.preset
    end

    def apply_preset_settings_overrides!(overrides, preset_settings, only_non_defaults:)
      defaults = ::ConversationSettings::PresetSettings.new

      apply_string = lambda do |key, value, default|
        value = value.to_s
        default = default.to_s
        return if only_non_defaults && value == default

        overrides[key] = value
      end

      apply_bool = lambda do |key, value, default|
        return if only_non_defaults && value == default

        overrides[key] = value
      end

      apply_int = lambda do |key, value, default|
        value = normalize_non_negative_integer(value)
        default = normalize_non_negative_integer(default)
        return if only_non_defaults && value == default

        overrides[key] = value
      end

      apply_string.call(:main_prompt, preset_settings.main_prompt, defaults.main_prompt)
      apply_string.call(:post_history_instructions, preset_settings.post_history_instructions, defaults.post_history_instructions)

      apply_string.call(:new_chat_prompt, preset_settings.new_chat_prompt, defaults.new_chat_prompt)
      apply_string.call(:new_group_chat_prompt, preset_settings.new_group_chat_prompt, defaults.new_group_chat_prompt)
      apply_string.call(:new_example_chat, preset_settings.new_example_chat, defaults.new_example_chat)
      apply_string.call(:group_nudge_prompt, preset_settings.group_nudge_prompt, defaults.group_nudge_prompt)
      apply_string.call(:continue_nudge_prompt, preset_settings.continue_nudge_prompt, defaults.continue_nudge_prompt)
      apply_string.call(:replace_empty_message, preset_settings.replace_empty_message, defaults.replace_empty_message)

      apply_bool.call(:continue_prefill, preset_settings.continue_prefill == true, defaults.continue_prefill == true)
      apply_string.call(:continue_postfix, preset_settings.continue_postfix, defaults.continue_postfix)
      apply_bool.call(:prefer_char_prompt, preset_settings.prefer_char_prompt != false, defaults.prefer_char_prompt != false)
      apply_bool.call(:prefer_char_instructions, preset_settings.prefer_char_instructions != false, defaults.prefer_char_instructions != false)
      apply_bool.call(:squash_system_messages, preset_settings.squash_system_messages == true, defaults.squash_system_messages == true)

      examples_behavior = ::TavernKit::Coerce.examples_behavior(preset_settings.examples_behavior)
      examples_behavior_default = ::TavernKit::Coerce.examples_behavior(defaults.examples_behavior)
      overrides[:examples_behavior] = examples_behavior unless only_non_defaults && examples_behavior == examples_behavior_default

      apply_int.call(:message_token_overhead, preset_settings.message_token_overhead, defaults.message_token_overhead)

      apply_string.call(:enhance_definitions, preset_settings.enhance_definitions, defaults.enhance_definitions)
      apply_string.call(:auxiliary_prompt, preset_settings.auxiliary_prompt, defaults.auxiliary_prompt)

      apply_string.call(:wi_format, preset_settings.wi_format, defaults.wi_format)
      apply_string.call(:scenario_format, preset_settings.scenario_format, defaults.scenario_format)
      apply_string.call(:personality_format, preset_settings.personality_format, defaults.personality_format)

      overrides
    end

    def speaker_generation_settings
      return {} unless @speaker

      llm = @speaker.llm_settings
      provider_id = @speaker.provider_identification
      return {} if provider_id.blank?

      defaults = {
        "max_context_tokens" => @default_max_context_tokens,
        "max_response_tokens" => @default_max_response_tokens,
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
  end
end
