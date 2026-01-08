# frozen_string_literal: true

require_relative "prompt/prompt_entry"
require_relative "utils"

module TavernKit
  # A prompt preset configuration inspired by SillyTavern's Prompt Manager.
  #
  # Contains settings for:
  # - Main Prompt (System Prompt)
  # - Post-History Instructions (PHI)
  # - Author's Note configuration
  # - World Info/Lore settings
  # - Token budget controls
  # - Character override preferences
  #
  # @example Basic usage
  #   preset = TavernKit::Preset.new(
  #     main_prompt: "You are a helpful assistant.",
  #     context_window_tokens: 8192,
  #     reserved_response_tokens: 512
  #   )
  #
  # @example Load from SillyTavern preset file
  #   preset = TavernKit::Preset.load_st_preset_file("my_preset.json")
  class Preset
    DEFAULT_MAIN_PROMPT = "Write {{char}}'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}."
    DEFAULT_ENHANCE_DEFINITIONS = "If you have more knowledge of {{char}}, add to the character's lore and personality to enhance them but keep the Character Sheet's definitions absolute."
    DEFAULT_NEW_CHAT_PROMPT = "[Start a new Chat]"
    DEFAULT_NEW_GROUP_CHAT_PROMPT = "[Start a new group chat. Group members: {{group}}]"
    DEFAULT_GROUP_NUDGE_PROMPT = "[Write the next reply only as {{char}}.]"
    DEFAULT_CONTINUE_NUDGE_PROMPT = "[Continue your last message without repeating its original content.]"
    DEFAULT_IMPERSONATION_PROMPT = "[Write your next reply from the point of view of {{user}}, using the chat history so far as a guideline for the writing style of {{user}}. Don't write as {{char}} or system. Don't describe actions of {{char}}.]"
    DEFAULT_SQUASH_SYSTEM_MESSAGES = false
    DEFAULT_CONTINUE_PREFILL = false
    DEFAULT_CONTINUE_POSTFIX = " "
    DEFAULT_WI_FORMAT = "{0}"
    DEFAULT_SCENARIO_FORMAT = "{{scenario}}"
    DEFAULT_PERSONALITY_FORMAT = "{{personality}}"
    # SillyTavern defaults (authors-note.js loadSettings):
    # - position: IN_CHAT (1)
    # - depth: 4
    # - role: SYSTEM
    DEFAULT_AUTHORS_NOTE_POSITION = :in_chat
    DEFAULT_AUTHORS_NOTE_DEPTH = 4
    DEFAULT_AUTHORS_NOTE_ROLE = :system

    CONFIG_KEYS = %i[
      main_prompt
      post_history_instructions
      new_example_chat
      new_chat_prompt
      new_group_chat_prompt
      group_nudge_prompt
      continue_nudge_prompt
      impersonation_prompt
      squash_system_messages
      continue_prefill
      continue_postfix
      replace_empty_message
      authors_note
      authors_note_frequency
      authors_note_position
      authors_note_depth
      authors_note_role
      authors_note_allow_wi_scan
      enhance_definitions
      auxiliary_prompt
      pinned_group_resolver
      prefer_char_prompt
      prefer_char_instructions
      character_lore_insertion_strategy
      prompt_entries
      context_window_tokens
      reserved_response_tokens
      message_token_overhead
      examples_behavior
      world_info_depth
      world_info_budget
      world_info_budget_cap
      world_info_include_names
      world_info_min_activations
      world_info_min_activations_depth_max
      world_info_use_group_scoring
      wi_format
      scenario_format
      personality_format
      instruct
      context_template
    ].freeze

    # @return [String] main system prompt template
    attr_reader :main_prompt

    # @return [String] post-history instructions
    attr_reader :post_history_instructions

    # @return [String] new example chat separator
    attr_reader :new_example_chat

    # @return [String] new chat prompt
    attr_reader :new_chat_prompt

    # @return [String] new group chat prompt
    attr_reader :new_group_chat_prompt

    # @return [String] group nudge prompt
    attr_reader :group_nudge_prompt

    # @return [String] continue nudge prompt
    attr_reader :continue_nudge_prompt

    # @return [String] impersonation prompt (used by :impersonate generation)
    attr_reader :impersonation_prompt

    # @return [Boolean] whether to squash system messages
    attr_reader :squash_system_messages

    # @return [Boolean] whether to use continue prefill
    attr_reader :continue_prefill

    # @return [String] continue postfix
    attr_reader :continue_postfix

    # @return [String] replacement for empty messages
    attr_reader :replace_empty_message

    # @return [String] author's note content
    attr_reader :authors_note

    # @return [Integer] author's note frequency
    attr_reader :authors_note_frequency

    # @return [Symbol] author's note position (:in_prompt, :in_chat, :before_prompt)
    attr_reader :authors_note_position

    # @return [Integer] author's note depth
    attr_reader :authors_note_depth

    # @return [Symbol] author's note role (:system, :user, :assistant)
    attr_reader :authors_note_role

    # @return [Boolean] allow World Info to scan Author's Note content
    attr_reader :authors_note_allow_wi_scan

    # @return [String] enhance definitions prompt
    attr_reader :enhance_definitions

    # @return [String] auxiliary prompt
    attr_reader :auxiliary_prompt

    # @return [Proc, nil] pinned group resolver callback
    attr_reader :pinned_group_resolver

    # @return [Boolean] prefer character card system prompt
    attr_reader :prefer_char_prompt

    # @return [Boolean] prefer character card instructions
    attr_reader :prefer_char_instructions

    # @return [Symbol] character lore insertion strategy
    attr_reader :character_lore_insertion_strategy

    # @return [Array<Prompt::PromptEntry>, nil] custom prompt entries
    attr_reader :prompt_entries

    # @return [Integer, nil] context window token limit
    attr_reader :context_window_tokens

    # @return [Integer] reserved tokens for response
    attr_reader :reserved_response_tokens

    # @return [Integer] per-message token overhead
    attr_reader :message_token_overhead

    # @return [Symbol] examples behavior (:gradually_push_out, :always_keep, :disabled)
    attr_reader :examples_behavior

    # @return [Integer, nil] world info scan depth
    attr_reader :world_info_depth

    # @return [Integer, nil] world info token budget
    attr_reader :world_info_budget

    # @return [Integer] world info budget cap
    attr_reader :world_info_budget_cap

    # @return [Boolean] include names in world info
    attr_reader :world_info_include_names

    # @return [Integer] minimum world info activations
    attr_reader :world_info_min_activations

    # @return [Integer] max depth for min activations
    attr_reader :world_info_min_activations_depth_max

    # @return [Boolean] use group scoring for world info
    attr_reader :world_info_use_group_scoring

    # @return [String] world info format template
    attr_reader :wi_format

    # @return [String] scenario format template
    attr_reader :scenario_format

    # @return [String] personality format template
    attr_reader :personality_format

    # @return [Instruct, nil] instruct mode settings
    attr_reader :instruct

    # @return [ContextTemplate, nil] context template settings
    attr_reader :context_template

    # Create a new Preset.
    #
    # @param main_prompt [String] main system prompt template
    # @param post_history_instructions [String] post-history instructions
    # @param new_example_chat [String] new example chat separator
    # @param new_chat_prompt [String] new chat prompt
    # @param new_group_chat_prompt [String] new group chat prompt
    # @param group_nudge_prompt [String] group nudge prompt
    # @param continue_nudge_prompt [String] continue nudge prompt
    # @param impersonation_prompt [String] impersonation prompt (used by :impersonate generation)
    # @param squash_system_messages [Boolean] whether to squash system messages
    # @param continue_prefill [Boolean] whether to use continue prefill
    # @param continue_postfix [String] continue postfix
    # @param replace_empty_message [String] replacement for empty messages
    # @param authors_note [String] author's note content
    # @param authors_note_frequency [Integer] author's note frequency
    # @param authors_note_position [Symbol] author's note position
    # @param authors_note_depth [Integer] author's note depth
    # @param authors_note_role [Symbol] author's note role
    # @param enhance_definitions [String] enhance definitions prompt
    # @param auxiliary_prompt [String] auxiliary prompt
    # @param pinned_group_resolver [Proc, nil] pinned group resolver callback
    # @param prefer_char_prompt [Boolean] prefer character card system prompt
    # @param prefer_char_instructions [Boolean] prefer character card instructions
    # @param character_lore_insertion_strategy [Symbol] character lore insertion strategy
    # @param prompt_entries [Array<Prompt::PromptEntry>, nil] custom prompt entries
    # @param context_window_tokens [Integer, nil] context window token limit
    # @param reserved_response_tokens [Integer] reserved tokens for response
    # @param message_token_overhead [Integer] per-message token overhead
    # @param examples_behavior [Symbol] examples behavior
    # @param world_info_depth [Integer, nil] world info scan depth
    # @param world_info_budget [Integer, nil] world info token budget
    # @param world_info_budget_cap [Integer] world info budget cap
    # @param world_info_include_names [Boolean] include names in world info
    # @param world_info_min_activations [Integer] minimum world info activations
    # @param world_info_min_activations_depth_max [Integer] max depth for min activations
    # @param world_info_use_group_scoring [Boolean] use group scoring for world info
    # @param wi_format [String] world info format template
    # @param scenario_format [String] scenario format template
    # @param personality_format [String] personality format template
    # @param instruct [Instruct, Hash, nil] instruct mode settings
    # @param context_template [ContextTemplate, Hash, nil] context template settings
    def initialize(
      main_prompt: DEFAULT_MAIN_PROMPT,
      post_history_instructions: "",
      new_example_chat: "",
      new_chat_prompt: "",
      new_group_chat_prompt: "",
      group_nudge_prompt: "",
      continue_nudge_prompt: "",
      impersonation_prompt: DEFAULT_IMPERSONATION_PROMPT,
      squash_system_messages: DEFAULT_SQUASH_SYSTEM_MESSAGES,
      continue_prefill: DEFAULT_CONTINUE_PREFILL,
      continue_postfix: DEFAULT_CONTINUE_POSTFIX,
      replace_empty_message: "",
      authors_note: "",
      authors_note_frequency: 1,
      authors_note_position: DEFAULT_AUTHORS_NOTE_POSITION,
      authors_note_depth: DEFAULT_AUTHORS_NOTE_DEPTH,
      authors_note_role: DEFAULT_AUTHORS_NOTE_ROLE,
      authors_note_allow_wi_scan: false,
      enhance_definitions: DEFAULT_ENHANCE_DEFINITIONS,
      auxiliary_prompt: "",
      pinned_group_resolver: nil,
      prefer_char_prompt: true,
      prefer_char_instructions: true,
      character_lore_insertion_strategy: :character_lore_first,
      prompt_entries: nil,
      context_window_tokens: nil,
      reserved_response_tokens: 0,
      message_token_overhead: 4,
      examples_behavior: :gradually_push_out,
      world_info_depth: nil,
      world_info_budget: nil,
      world_info_budget_cap: 0,
      world_info_include_names: true,
      world_info_min_activations: 0,
      world_info_min_activations_depth_max: 0,
      world_info_use_group_scoring: false,
      wi_format: DEFAULT_WI_FORMAT,
      scenario_format: DEFAULT_SCENARIO_FORMAT,
      personality_format: DEFAULT_PERSONALITY_FORMAT,
      instruct: nil,
      context_template: nil
    )
      @main_prompt = main_prompt
      @post_history_instructions = post_history_instructions
      @new_example_chat = new_example_chat
      @new_chat_prompt = new_chat_prompt
      @new_group_chat_prompt = new_group_chat_prompt
      @group_nudge_prompt = group_nudge_prompt
      @continue_nudge_prompt = continue_nudge_prompt
      @impersonation_prompt = impersonation_prompt
      @squash_system_messages = squash_system_messages
      @continue_prefill = continue_prefill
      @continue_postfix = continue_postfix
      @replace_empty_message = replace_empty_message
      @authors_note = authors_note
      @authors_note_frequency = [authors_note_frequency, 0].max
      @authors_note_position = authors_note_position
      @authors_note_depth = authors_note_depth
      @authors_note_role = authors_note_role
      @authors_note_allow_wi_scan = authors_note_allow_wi_scan
      @enhance_definitions = enhance_definitions
      @auxiliary_prompt = auxiliary_prompt
      @pinned_group_resolver = pinned_group_resolver
      @prefer_char_prompt = prefer_char_prompt
      @prefer_char_instructions = prefer_char_instructions
      @character_lore_insertion_strategy = character_lore_insertion_strategy
      @prompt_entries = prompt_entries
      @context_window_tokens = context_window_tokens
      @reserved_response_tokens = reserved_response_tokens
      @message_token_overhead = message_token_overhead
      @examples_behavior = examples_behavior
      @world_info_depth = world_info_depth
      @world_info_budget = world_info_budget
      @world_info_budget_cap = world_info_budget_cap
      @world_info_include_names = world_info_include_names
      @world_info_min_activations = world_info_min_activations
      @world_info_min_activations_depth_max = world_info_min_activations_depth_max
      @world_info_use_group_scoring = world_info_use_group_scoring
      @wi_format = wi_format
      @scenario_format = scenario_format
      @personality_format = personality_format
      @instruct = coerce_instruct(instruct)
      @context_template = coerce_context_template(context_template)
    end

    # Get the effective Instruct settings, falling back to defaults.
    #
    # @return [Instruct]
    def effective_instruct
      @instruct || Instruct.new
    end

    # Get the effective ContextTemplate settings, falling back to defaults.
    #
    # @return [ContextTemplate]
    def effective_context_template
      @context_template || ContextTemplate.new
    end

    def effective_prompt_entries
      prompt_entries || self.class.default_prompt_entries
    end

    def to_h
      CONFIG_KEYS.to_h { |key| [key, public_send(key)] }
    end

    def with(**overrides)
      Preset.new(**to_h.merge(overrides))
    end

    def max_input_tokens
      return nil if context_window_tokens.nil?
      [context_window_tokens.to_i - reserved_response_tokens.to_i, 0].max
    end

    def self.default_prompt_entries
      @default_prompt_entries ||= [
        Prompt::PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "world_info_before_char_defs", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "persona_description", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "character_description", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "character_personality", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "scenario", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "enhance_definitions", pinned: true, role: :system, enabled: false),
        Prompt::PromptEntry.new(id: "auxiliary_prompt", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "world_info_after_char_defs", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "world_info_before_example_messages", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "chat_examples", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "world_info_after_example_messages", pinned: true, role: :system),
        Prompt::PromptEntry.new(
          id: "authors_note",
          pinned: true,
          role: DEFAULT_AUTHORS_NOTE_ROLE,
          position: DEFAULT_AUTHORS_NOTE_POSITION,
          depth: DEFAULT_AUTHORS_NOTE_DEPTH,
        ),
        Prompt::PromptEntry.new(id: "chat_history", pinned: true, role: :system),
        Prompt::PromptEntry.new(id: "post_history_instructions", pinned: true, role: :system),
      ]
    end

    # Load a Preset from SillyTavern preset JSON format.
    #
    # ST preset JSON structure:
    # - `prompts`: array of prompt entries (with identifier, role, content, etc.)
    # - `prompt_order`: array defining order and enabled state (takes precedence)
    # - `openai_max_context`: context window size
    # - `openai_max_tokens`: max response tokens
    #
    # @param hash [Hash] parsed JSON from ST preset file
    # @return [Preset]
    def self.from_st_preset_json(hash)
      Preset::StImporter.new(hash).to_preset
    end

    # Load a Preset from an ST preset JSON file.
    #
    # @param path [String] path to the JSON file
    # @return [Preset]
    def self.load_st_preset_file(path)
      Preset::StImporter.load_file(path)
    end

    private

    def coerce_instruct(value)
      return nil if value.nil?
      return value if value.is_a?(Instruct)
      return Instruct.from_st_json(value) if value.is_a?(Hash)

      nil
    end

    def coerce_context_template(value)
      return nil if value.nil?
      return value if value.is_a?(ContextTemplate)
      return ContextTemplate.from_st_json(value) if value.is_a?(Hash)

      nil
    end
  end
end

require_relative "preset/st_importer"
