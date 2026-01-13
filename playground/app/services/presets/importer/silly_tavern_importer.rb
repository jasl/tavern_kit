# frozen_string_literal: true

module Presets
  module Importer
    # Imports presets from SillyTavern OpenAI JSON format.
    #
    # Maps SillyTavern OpenAI preset fields to TavernKit's
    # generation_settings and preset_settings structure.
    #
    # @example Import a SillyTavern preset
    #   importer = SillyTavernImporter.new
    #   result = importer.call(data, user: current_user, filename: "Default.json")
    #
    class SillyTavernImporter < Base
      # Mapping of ST prompt identifiers to preset_settings fields
      PROMPT_MAPPINGS = {
        "main" => :main_prompt,
        "jailbreak" => :post_history_instructions,
        "nsfw" => :auxiliary_prompt,
        "enhanceDefinitions" => :enhance_definitions,
      }.freeze

      # Import a preset from SillyTavern OpenAI format.
      #
      # @param data [Hash] parsed JSON data
      # @param user [User] the user who owns the imported preset
      # @param filename [String, nil] original filename (for name fallback)
      # @return [ImportResult] the import result
      def call(data, user:, filename: nil)
        name = determine_name(data, filename)
        unique_name = ensure_unique_name(name, user)

        generation_settings = extract_generation_settings(data)
        preset_settings = extract_preset_settings(data)

        preset = create_preset(
          {
            name: unique_name,
            description: "Imported from SillyTavern",
            generation_settings: generation_settings,
            preset_settings: preset_settings,
          },
          user: user
        )

        ImportResult.success(preset)
      rescue ActiveRecord::RecordInvalid => e
        ImportResult.failure("Failed to create preset: #{e.message}")
      end

      private

      def extract_generation_settings(data)
        {
          temperature: data["temperature"],
          top_p: data["top_p"],
          top_k: data["top_k"],
          repetition_penalty: data["repetition_penalty"],
          max_response_tokens: data["openai_max_tokens"],
          max_context_tokens: data["openai_max_context"],
        }.compact
      end

      def extract_preset_settings(data)
        settings = {}

        # Extract from prompts array
        if data["prompts"].is_a?(Array)
          extract_prompts_from_array(data["prompts"], settings)
        end

        # Direct field mappings
        settings[:new_chat_prompt] = data["new_chat_prompt"] if data["new_chat_prompt"].present?
        settings[:new_group_chat_prompt] = data["new_group_chat_prompt"] if data["new_group_chat_prompt"].present?
        settings[:new_example_chat] = data["new_example_chat_prompt"] if data["new_example_chat_prompt"].present?
        settings[:continue_nudge_prompt] = data["continue_nudge_prompt"] if data["continue_nudge_prompt"].present?
        settings[:group_nudge_prompt] = data["group_nudge_prompt"] if data["group_nudge_prompt"].present?
        settings[:impersonation_prompt] = data["impersonation_prompt"] if data["impersonation_prompt"].present?
        settings[:replace_empty_message] = data["send_if_empty"] if data["send_if_empty"].present?

        # Format templates
        settings[:wi_format] = data["wi_format"] if data["wi_format"].present?
        settings[:scenario_format] = data["scenario_format"] if data["scenario_format"].present?
        settings[:personality_format] = data["personality_format"] if data["personality_format"].present?

        # Boolean settings
        settings[:squash_system_messages] = data["squash_system_messages"] if data.key?("squash_system_messages")
        settings[:continue_prefill] = data["continue_prefill"] if data.key?("continue_prefill")
        settings[:continue_postfix] = data["continue_postfix"] if data["continue_postfix"].present?

        settings.compact
      end

      def extract_prompts_from_array(prompts, settings)
        prompts.each do |prompt|
          next unless prompt.is_a?(Hash)
          next if prompt["marker"] # Skip marker entries

          identifier = prompt["identifier"]
          content = prompt["content"]

          next if identifier.blank? || content.blank?

          field = PROMPT_MAPPINGS[identifier]
          settings[field] = content if field
        end
      end
    end
  end
end
