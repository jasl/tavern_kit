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
      preset_settings = prompt_settings&.preset

      raw_prompt_settings = @space.read_attribute_before_type_cast("prompt_settings")
      has_explicit_preset_settings = raw_prompt_settings.is_a?(Hash) && raw_prompt_settings["preset"].present?
      should_apply_preset_overrides = @preset.nil? || has_explicit_preset_settings

      if preset_settings && should_apply_preset_overrides
        overrides[:main_prompt] = preset_settings.main_prompt.to_s if preset_settings.main_prompt.present?
        if preset_settings.post_history_instructions.present?
          overrides[:post_history_instructions] = preset_settings.post_history_instructions.to_s
        end
        overrides[:new_chat_prompt] = preset_settings.new_chat_prompt.to_s if preset_settings.new_chat_prompt.present?
        overrides[:new_group_chat_prompt] = preset_settings.new_group_chat_prompt.to_s if preset_settings.new_group_chat_prompt.present?
        overrides[:new_example_chat] = preset_settings.new_example_chat.to_s if preset_settings.new_example_chat.present?
        overrides[:group_nudge_prompt] = preset_settings.group_nudge_prompt.to_s if preset_settings.group_nudge_prompt.present?
        overrides[:continue_nudge_prompt] = preset_settings.continue_nudge_prompt.to_s if preset_settings.continue_nudge_prompt.present?
        overrides[:replace_empty_message] = preset_settings.replace_empty_message.to_s if preset_settings.replace_empty_message.present?

        overrides[:continue_prefill] = preset_settings.continue_prefill == true
        overrides[:continue_postfix] = preset_settings.continue_postfix.to_s if preset_settings.continue_postfix.present?
        overrides[:prefer_char_prompt] = preset_settings.prefer_char_prompt != false
        overrides[:prefer_char_instructions] = preset_settings.prefer_char_instructions != false
        overrides[:squash_system_messages] = preset_settings.squash_system_messages == true
        overrides[:examples_behavior] = ::TavernKit::Coerce.examples_behavior(preset_settings.examples_behavior) if preset_settings.examples_behavior.present?
        overrides[:message_token_overhead] = normalize_non_negative_integer(preset_settings.message_token_overhead) if preset_settings.message_token_overhead

        overrides[:enhance_definitions] = preset_settings.enhance_definitions.to_s if preset_settings.enhance_definitions.present?
        overrides[:auxiliary_prompt] = preset_settings.auxiliary_prompt.to_s if preset_settings.auxiliary_prompt.present?

        overrides.merge!(
          ::PromptBuilding::AuthorsNoteResolver
            .new(conversation: @conversation, speaker: @speaker, preset_settings: preset_settings)
            .call
        )

        overrides[:wi_format] = preset_settings.wi_format.to_s if preset_settings.wi_format.present?
        overrides[:scenario_format] = preset_settings.scenario_format.to_s if preset_settings.scenario_format.present?
        overrides[:personality_format] = preset_settings.personality_format.to_s if preset_settings.personality_format.present?
      end

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
