# frozen_string_literal: true

require "json"

require_relative "../utils"
require_relative "../prompt/prompt_entry"

module TavernKit
  class Preset
    # Responsible for importing SillyTavern preset JSON into a Preset.
    # Keeps ST-specific parsing logic out of the core Preset model.
    class StImporter
      # ST pinned prompt identifiers.
      #
      # Only IDs in this map are treated as "pinned" (built-in placeholders).
      # Unknown IDs with system_prompt=true should be treated as custom prompts,
      # not pinned, to avoid data loss.
      #
      # This mapping includes:
      # - Standard ST identifiers (camelCase format)
      # - Alternative identifiers found in various ST presets/exports
      # - Compatibility aliases for older preset formats
      ST_PINNED_IDS = {
        # Core prompts
        "main" => "main_prompt",
        "mainPrompt" => "main_prompt",
        "jailbreak" => "post_history_instructions",
        "postHistoryInstructions" => "post_history_instructions",

        # Character information
        "personaDescription" => "persona_description",
        "persona_description" => "persona_description",
        "charDescription" => "character_description",
        "character_description" => "character_description",
        "charPersonality" => "character_personality",
        "character_personality" => "character_personality",
        "scenario" => "scenario",

        # Auxiliary/NSFW prompts
        "nsfw" => "auxiliary_prompt",
        "auxiliaryPrompt" => "auxiliary_prompt",
        "auxiliary_prompt" => "auxiliary_prompt",
        "enhanceDefinitions" => "enhance_definitions",
        "enhance_definitions" => "enhance_definitions",

        # Chat related
        "dialogueExamples" => "chat_examples",
        "dialogue_examples" => "chat_examples",
        "chat_examples" => "chat_examples",
        "chatHistory" => "chat_history",
        "chat_history" => "chat_history",

        # World Info positions (ST uses camelCase)
        "worldInfoBefore" => "world_info_before_char_defs",
        "worldInfoAfter" => "world_info_after_char_defs",
        "world_info_before" => "world_info_before_char_defs",
        "world_info_after" => "world_info_after_char_defs",

        # Additional World Info positions (for extended presets)
        "worldInfoBeforeExamples" => "world_info_before_example_messages",
        "worldInfoAfterExamples" => "world_info_after_example_messages",
        "world_info_before_examples" => "world_info_before_example_messages",
        "world_info_after_examples" => "world_info_after_example_messages",

        # Author's Note
        "authorsNote" => "authors_note",
        "authors_note" => "authors_note",
      }.freeze

      def self.load_file(path)
        new(JSON.parse(File.read(path))).to_preset
      end

      def initialize(hash)
        @hash = Utils.deep_stringify_keys(hash)
      end

      def to_preset
        hash = @hash
        pinned_group_resolver = hash["pinned_group_resolver"]

        # Build prompts lookup for fallback extraction
        prompts_by_id = build_prompts_by_id(hash["prompts"])

        # Core text prompts live in the Prompt Manager `prompts[]` array.
        main_prompt = prompts_by_id.dig("main", "content")
        main_prompt = Preset::DEFAULT_MAIN_PROMPT if main_prompt.nil? || main_prompt.to_s.strip.empty?

        phi = prompts_by_id.dig("jailbreak", "content").to_s

        # Extract other fields
        new_example_chat = hash["new_example_chat_prompt"]
        new_chat_prompt = hash["new_chat_prompt"]
        new_group_chat_prompt = hash["new_group_chat_prompt"]
        group_nudge_prompt = hash["group_nudge_prompt"]
        continue_nudge_prompt = hash["continue_nudge_prompt"]
        squash_system_messages = fetch_bool(hash, "squash_system_messages", default: Preset::DEFAULT_SQUASH_SYSTEM_MESSAGES)
        continue_prefill = fetch_bool(hash, "continue_prefill", default: Preset::DEFAULT_CONTINUE_PREFILL)
        continue_postfix = coerce_st_continue_postfix(hash["continue_postfix"])
        replace_empty_message = hash["send_if_empty"].to_s
        wi_format = hash["wi_format"]
        scenario_format = hash["scenario_format"]
        personality_format = hash["personality_format"]
        authors_note = hash["authors_note"].to_s
        authors_note_frequency = [((hash["authors_note_frequency"] || 1).to_i), 0].max
        authors_note_position = Coerce.authors_note_position(hash["authors_note_position"], default: Preset::DEFAULT_AUTHORS_NOTE_POSITION)
        authors_note_depth = hash["authors_note_depth"].nil? ? Preset::DEFAULT_AUTHORS_NOTE_DEPTH : [hash["authors_note_depth"].to_i, 0].max
        authors_note_role = Coerce.role(hash["authors_note_role"], default: Preset::DEFAULT_AUTHORS_NOTE_ROLE)
        authors_note_allow_wi_scan = fetch_bool(hash, "allowWIScan", default: false)

        # Pinned built-ins live in `prompts[]`.
        enhance_definitions = prompts_by_id.dig("enhanceDefinitions", "content")
        auxiliary_prompt = prompts_by_id.dig("nsfw", "content").to_s

        # Preference flags
        prefer_char_prompt = fetch_bool(hash, "prefer_character_prompt", default: true)
        prefer_char_instructions = fetch_bool(hash, "prefer_character_jailbreak", default: true)

        # Context settings
        context_window = hash["openai_max_context"]
        context_window = context_window.nil? ? nil : context_window.to_i
        reserved_response = [((hash["openai_max_tokens"] || 0).to_i), 0].max
        message_overhead = [(hash["message_token_overhead"] || 4).to_i, 0].max

        # World Info settings
        world_info_depth = hash["world_info_depth"]
        world_info_depth = world_info_depth.nil? ? nil : [world_info_depth.to_i, 0].max
        world_info_budget = hash["world_info_budget"]
        world_info_budget = world_info_budget.nil? ? nil : [world_info_budget.to_i, 0].max
        world_info_budget_cap = [hash["world_info_budget_cap"].to_i, 0].max
        world_info_include_names = fetch_bool(hash, "world_info_include_names", default: true)
        world_info_min_activations = [((hash["world_info_min_activations"] || 0).to_i), 0].max
        world_info_min_activations_depth_max = [((hash["world_info_min_activations_depth_max"] || 0).to_i), 0].max
        world_info_use_group_scoring = fetch_bool(hash, "world_info_use_group_scoring", default: false)

        # Build prompt entries from ST's prompts + prompt_order
        prompt_entries = build_prompt_entries_from_st(hash)

        # Extract instruct mode settings
        instruct = extract_instruct_settings(hash)

        # Extract context template settings
        context_template = extract_context_settings(hash)

        new_chat_prompt = Preset::DEFAULT_NEW_CHAT_PROMPT if new_chat_prompt.nil?
        new_group_chat_prompt = Preset::DEFAULT_NEW_GROUP_CHAT_PROMPT if new_group_chat_prompt.nil?
        new_example_chat = Preset::DEFAULT_NEW_EXAMPLE_CHAT_PROMPT if new_example_chat.nil?
        group_nudge_prompt = Preset::DEFAULT_GROUP_NUDGE_PROMPT if group_nudge_prompt.nil?
        continue_nudge_prompt = Preset::DEFAULT_CONTINUE_NUDGE_PROMPT if continue_nudge_prompt.nil?
        continue_postfix = Preset::DEFAULT_CONTINUE_POSTFIX if continue_postfix.nil?
        wi_format = Preset::DEFAULT_WI_FORMAT if wi_format.nil?
        scenario_format = Preset::DEFAULT_SCENARIO_FORMAT if scenario_format.nil?
        personality_format = Preset::DEFAULT_PERSONALITY_FORMAT if personality_format.nil?

        Preset.new(
          main_prompt: main_prompt,
          post_history_instructions: phi.to_s,
          new_example_chat: new_example_chat.to_s,
          new_chat_prompt: new_chat_prompt,
          new_group_chat_prompt: new_group_chat_prompt,
          group_nudge_prompt: group_nudge_prompt,
          continue_nudge_prompt: continue_nudge_prompt,
          squash_system_messages: squash_system_messages,
          continue_prefill: continue_prefill,
          continue_postfix: continue_postfix,
          replace_empty_message: replace_empty_message,
          authors_note: authors_note,
          authors_note_frequency: authors_note_frequency,
          authors_note_position: authors_note_position,
          authors_note_depth: authors_note_depth,
          authors_note_role: authors_note_role,
          authors_note_allow_wi_scan: authors_note_allow_wi_scan,
          enhance_definitions: enhance_definitions.nil? ? Preset::DEFAULT_ENHANCE_DEFINITIONS : enhance_definitions.to_s,
          auxiliary_prompt: auxiliary_prompt,
          pinned_group_resolver: pinned_group_resolver,
          prefer_char_prompt: prefer_char_prompt,
          prefer_char_instructions: prefer_char_instructions,
          prompt_entries: prompt_entries,
          context_window_tokens: context_window,
          reserved_response_tokens: reserved_response,
          message_token_overhead: message_overhead,
          world_info_depth: world_info_depth,
          world_info_budget: world_info_budget,
          world_info_budget_cap: world_info_budget_cap,
          world_info_include_names: world_info_include_names,
          world_info_min_activations: world_info_min_activations,
          world_info_min_activations_depth_max: world_info_min_activations_depth_max,
          world_info_use_group_scoring: world_info_use_group_scoring,
          wi_format: wi_format,
          scenario_format: scenario_format,
          personality_format: personality_format,
          instruct: instruct,
          context_template: context_template,
        )
      end

      private

      def fetch_bool(hash, *keys, default:)
        keys.each do |key|
          return booleanish(hash[key]) if hash.key?(key)
        end
        default
      end

      def booleanish(value)
        case value
        in true | false then value
        else
          case value.to_s.strip.downcase
          in "1" | "true" | "yes" | "y" | "on" then true
          in "0" | "false" | "no" | "n" | "off" then false
          else !!value
          end
        end
      end

      # Build a lookup hash of prompts by identifier for fallback extraction.
      # Used by P0-3 to read main/jailbreak text from prompts[] when top-level fields are empty.
      #
      # @param prompts [Array, nil] the prompts array from ST preset
      # @return [Hash] lookup by identifier
      def build_prompts_by_id(prompts)
        return {} unless prompts.is_a?(Array)

        result = {}
        prompts.each do |p|
          next unless p.is_a?(Hash)
          id = p["identifier"]
          next if id.nil?
          result[id.to_s] = p
        end
        result
      end

      # Build prompt entries from ST's prompts array and prompt_order.
      #
      # ST has two arrays:
      # - `prompts`: defines the prompt entries (identifier, role, content, etc.)
      # - `prompt_order`: defines the order and enabled state
      #
      # prompt_order can have two formats:
      # - Flat array: `[{ identifier: "main", enabled: true }, ...]`
      # - Nested array: `[{ character_id: 100000, order: [...] }, ...]`
      #
      # For nested format, we look for character_id=100000 (global/default) or use first bucket.
      #
      # prompt_order takes precedence for ordering and enabled state.
      def build_prompt_entries_from_st(hash)
        prompts = hash["prompts"] || []
        prompt_order = extract_prompt_order_entries(hash["prompt_order"])

        # Build a lookup of prompts by identifier
        prompts_by_id = {}
        prompts.each do |p|
          id = p["identifier"]
          next if id.nil?
          prompts_by_id[id] = p
        end

        entries = []

        if prompt_order.is_a?(Array) && prompt_order.any?
          # Use prompt_order for ordering and enabled state
          prompt_order.each do |order_entry|
            id = order_entry["identifier"]
            next if id.nil?

            prompt_data = prompts_by_id[id] || {}
            enabled = order_entry.key?("enabled") ? booleanish(order_entry["enabled"]) : true

            entries << build_st_prompt_entry(id, prompt_data, enabled: enabled)
          end
        else
          # Fall back to prompts array order
          prompts.each do |p|
            id = p["identifier"]
            next if id.nil?
            entries << build_st_prompt_entry(id, p)
          end
        end

        # Return nil to use defaults if no entries found
        entries.empty? ? nil : entries
      end

      # Extract prompt order entries from ST's prompt_order field.
      #
      # Handles two formats:
      # 1. Flat array: `[{ identifier: "main", enabled: true }, ...]`
      # 2. Nested array: `[{ character_id: 100000, order: [...] }, ...]`
      #
      # For nested format, prefers character_id=100000 (global/default bucket).
      #
      # @param raw [Array, nil] the raw prompt_order value
      # @return [Array, nil] the extracted order entries array
      def extract_prompt_order_entries(raw)
        return nil unless raw.is_a?(Array) && raw.any?

        first = raw.first
        return raw unless first.is_a?(Hash)

        # Check if this is nested format (has "order" key)
        if first.key?("order")
          # Nested format: find global bucket (character_id=100000) or use first
          global_bucket = raw.find do |bucket|
            char_id = bucket["character_id"]
            char_id == 100_000
          end
          bucket = global_bucket || first
          Array(bucket["order"])
        else
          # Flat format: return as-is
          raw
        end
      end

      def build_st_prompt_entry(id, prompt_data, enabled: nil)
        # Normalize ST identifier to TavernKit id
        normalized_id = ST_PINNED_IDS[id] || id

        # P0-2 Fix: Only mark as pinned if we recognize the ID.
        # Unknown IDs with system_prompt=true should be treated as custom prompts
        # to avoid silent data loss when ST adds new built-in prompts.
        #
        # P2-1 Extension: Marker prompts (system_prompt=true, marker=true) represent built-in
        # placeholders in ST. For forward compatibility, treat unknown markers as pinned so
        # the builder can resolve them via pinned_group_resolver or emit a warning.
        marker = booleanish(prompt_data["marker"] || false)
        pinned = ST_PINNED_IDS.key?(id) || marker

        # Extract role (0=system, 1=user, 2=assistant in some ST versions)
        role = coerce_st_role(prompt_data["role"])

        # Extract position (injection_position: 0=relative, 1=in_chat)
        position = prompt_data["injection_position"] == 1 ? :in_chat : :relative

        # Extract depth and order
        depth = (prompt_data["injection_depth"] || 4).to_i
        order = (prompt_data["injection_order"] || 100).to_i

        # Extract content (for custom prompts)
        content = prompt_data["content"]
        content = content.nil? ? nil : content.to_s

        # Extract triggers (supports both string names and numeric codes)
        triggers = Coerce.triggers(prompt_data["injection_trigger"] || [])

        forbid_overrides = booleanish(prompt_data["forbid_overrides"] || false)

        # Enabled state
        enabled = booleanish(prompt_data["enabled"]) if enabled.nil? && prompt_data.key?("enabled")
        enabled = true if enabled.nil?

        Prompt::PromptEntry.new(
          id: normalized_id,
          name: prompt_data["name"] || normalized_id,
          enabled: enabled,
          pinned: pinned,
          role: role,
          position: position,
          depth: depth,
          order: order,
          content: content,
          triggers: triggers,
          forbid_overrides: forbid_overrides,
        )
      end

      def coerce_st_role(value)
        case value
        in 0 | "system" | "0" | nil then :system
        in 1 | "user" | "1" then :user
        in 2 | "assistant" | "2" then :assistant
        else :system
        end
      end

      def coerce_st_continue_postfix(value)
        return nil if value.nil?

        # ST uses string postfix values, but older exports/settings may contain numeric codes.
        # Match ST's `continue_postfix_types`: 0=>"", 1=>" ", 2=>"\\n", 3=>"\\n\\n"
        if value.is_a?(Integer)
          return "" if value == 0
          return " " if value == 1
          return "\n" if value == 2
          return "\n\n" if value == 3
        end

        if value.is_a?(String) && value.strip.match?(/\A\d+\z/)
          int_val = value.strip.to_i
          return coerce_st_continue_postfix(int_val)
        end

        value.to_s
      end

      # Extract instruct mode settings from ST preset.
      #
      # @param hash [Hash] the full preset hash
      # @return [Instruct, nil]
      def extract_instruct_settings(hash)
        instruct = hash["instruct"]
        return nil unless instruct.is_a?(Hash)

        Instruct.from_st_json(instruct)
      end

      # Extract context template settings from ST preset.
      #
      # @param hash [Hash] the full preset hash
      # @return [ContextTemplate, nil]
      def extract_context_settings(hash)
        context = hash["context"]
        return nil unless context.is_a?(Hash)

        ContextTemplate.from_st_json(context)
      end
    end
  end
end
