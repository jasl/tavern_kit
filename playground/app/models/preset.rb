# frozen_string_literal: true

# Preset stores reusable LLM settings configurations.
#
# Presets can be system-level (user_id = nil) or user-created.
# Each preset stores generation settings (temperature, top_p, etc.)
# and prompt settings (main_prompt, post_history_instructions, etc.).
#
# @example Get the default preset
#   Preset.get_default
#   # => #<Preset name: "Default", ...>
#
# @example Set default preset
#   Preset.set_default!(preset)
#
# @example Apply a preset to a membership
#   preset.apply_to(membership)
#
# @example Access structured settings
#   preset.generation_settings.temperature # => 1.0
#   preset.preset_settings.main_prompt # => "Write {{char}}'s..."
#
class Preset < ApplicationRecord
  # Serialize jsonb columns as structured Schema objects
  # Reuse ConversationSettings schemas to avoid duplication
  serialize :generation_settings, coder: EasyTalkCoder.new(ConversationSettings::LLM::GenerationSettings)
  serialize :preset_settings, coder: EasyTalkCoder.new(ConversationSettings::PresetSettings)

  belongs_to :llm_provider, optional: true
  belongs_to :user, optional: true

  has_many :space_memberships, dependent: :nullify

  validates :name, presence: true
  validates :name, uniqueness: { scope: :user_id, message: "has already been taken" }

  scope :system_presets, -> { where(user_id: nil) }
  scope :user_presets, -> { where.not(user_id: nil) }
  scope :by_name, -> { order(:name) }

  # System preset configurations (used for seeding)
  SYSTEM_PRESETS = {
    default: {
      name: "Default",
      description: "Balanced settings suitable for most use cases.",
      generation_settings: {
        max_context_tokens: 8192,
        max_response_tokens: 512,
        temperature: 1.0,
        top_p: 1.0,
        top_k: 0,
        repetition_penalty: 1.0,
      },
      preset_settings: {
        main_prompt: "Write {{char}}'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}.",
        post_history_instructions: "",
        group_nudge_prompt: "[Write the next reply only as {{char}}.]",
        continue_nudge_prompt: "[Continue your last message without repeating its original content.]",
        new_chat_prompt: "[Start a new Chat]",
        new_group_chat_prompt: "[Start a new group chat. Group members: {{group}}]",
        new_example_chat: "",
        replace_empty_message: "",
        continue_prefill: false,
        continue_postfix: " ",
        enhance_definitions: "If you have more knowledge of {{char}}, add to the character's lore and personality to enhance them but keep the Character Sheet's definitions absolute.",
        auxiliary_prompt: "",
        prefer_char_prompt: true,
        prefer_char_instructions: true,
        squash_system_messages: false,
        examples_behavior: "gradually_push_out",
        message_token_overhead: 4,
        authors_note: "",
        authors_note_frequency: 1,
        authors_note_position: "in_chat",
        authors_note_depth: 4,
        authors_note_role: "system",
        wi_format: "{0}",
        scenario_format: "{{scenario}}",
        personality_format: "{{personality}}",
      },
      is_default: true,
    },
    creative: {
      name: "Creative",
      description: "Higher temperature for more creative and varied outputs.",
      generation_settings: {
        max_context_tokens: 8192,
        max_response_tokens: 768,
        temperature: 1.3,
        top_p: 0.95,
        top_k: 40,
        repetition_penalty: 1.1,
      },
      preset_settings: {
        main_prompt: "Write {{char}}'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}. Be creative and descriptive.",
        post_history_instructions: "",
        group_nudge_prompt: "[Write the next reply only as {{char}}.]",
        continue_nudge_prompt: "[Continue your last message without repeating its original content.]",
        new_chat_prompt: "[Start a new Chat]",
        new_group_chat_prompt: "[Start a new group chat. Group members: {{group}}]",
        new_example_chat: "",
        replace_empty_message: "",
        continue_prefill: false,
        continue_postfix: " ",
        enhance_definitions: "If you have more knowledge of {{char}}, add to the character's lore and personality to enhance them but keep the Character Sheet's definitions absolute.",
        auxiliary_prompt: "",
        prefer_char_prompt: true,
        prefer_char_instructions: true,
        squash_system_messages: false,
        examples_behavior: "gradually_push_out",
        message_token_overhead: 4,
        authors_note: "",
        authors_note_frequency: 1,
        authors_note_position: "in_chat",
        authors_note_depth: 4,
        authors_note_role: "system",
        wi_format: "{0}",
        scenario_format: "{{scenario}}",
        personality_format: "{{personality}}",
      },
      is_default: false,
    },
    precise: {
      name: "Precise",
      description: "Lower temperature for more focused and deterministic outputs.",
      generation_settings: {
        max_context_tokens: 8192,
        max_response_tokens: 512,
        temperature: 0.7,
        top_p: 0.9,
        top_k: 20,
        repetition_penalty: 1.0,
      },
      preset_settings: {
        main_prompt: "Write {{char}}'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}.",
        post_history_instructions: "",
        group_nudge_prompt: "[Write the next reply only as {{char}}.]",
        continue_nudge_prompt: "[Continue your last message without repeating its original content.]",
        new_chat_prompt: "[Start a new Chat]",
        new_group_chat_prompt: "[Start a new group chat. Group members: {{group}}]",
        new_example_chat: "",
        replace_empty_message: "",
        continue_prefill: false,
        continue_postfix: " ",
        enhance_definitions: "",
        auxiliary_prompt: "",
        prefer_char_prompt: true,
        prefer_char_instructions: true,
        squash_system_messages: false,
        examples_behavior: "gradually_push_out",
        message_token_overhead: 4,
        authors_note: "",
        authors_note_frequency: 1,
        authors_note_position: "in_chat",
        authors_note_depth: 4,
        authors_note_role: "system",
        wi_format: "{0}",
        scenario_format: "{{scenario}}",
        personality_format: "{{personality}}",
      },
      is_default: false,
    },
  }.freeze

  class << self
    # Get the default preset.
    #
    # If no default is set (or the stored default points to a missing preset),
    # this method will pick a deterministic fallback, persist it to Settings,
    # and return it.
    #
    # @return [Preset, nil] the default preset (or nil if none exist)
    def get_default
      preset_id = Setting.get("preset.default_id").to_s
      if preset_id.match?(/\A\d+\z/)
        preset = find_by(id: preset_id)
        return preset if preset
      end

      # Ensure we have at least one preset so we don't return nil on a fresh DB.
      seed_system_presets! unless exists?

      preset = default_fallback_preset
      return unless preset

      set_default!(preset)
    end

    # Set a preset as the default.
    #
    # @param preset [Preset] the preset to set as default
    # @return [Preset] the preset
    def set_default!(preset)
      Setting.set("preset.default_id", preset.id)
      preset
    end

    # Seed system presets into the database.
    # Called from db/seeds.rb or on first run.
    #
    # @return [Array<Preset>] created/updated presets
    def seed_system_presets!
      SYSTEM_PRESETS.map do |_key, config|
        find_or_create_by!(name: config[:name], user_id: nil) do |preset|
          preset.description = config[:description]
          preset.generation_settings = config[:generation_settings]
          preset.preset_settings = config[:preset_settings]
          preset.is_default = config[:is_default]
        end
      end
    end

    # Get all presets for selection UI.
    #
    # @param user [User, nil] the user to include user presets for
    # @return [ActiveRecord::Relation] presets ordered for UI
    def for_select(user: nil)
      if user
        where(user_id: [nil, user.id]).order(:user_id, :name)
      else
        system_presets.by_name
      end
    end

    private

    # Choose a deterministic default preset when the Setting is missing/invalid.
    #
    # Prefer a built-in "Default" system preset if present.
    # Otherwise fall back to the oldest preset by ID.
    #
    # @return [Preset, nil]
    def default_fallback_preset
      find_by(is_default: true, user_id: nil) ||
        find_by(name: "Default", user_id: nil) ||
        system_presets.order(:id).first ||
        order(:id).first
    end
  end

  # Check if this is a system preset.
  #
  # @return [Boolean]
  def system_preset?
    user_id.nil?
  end

  # Check if this is a user-created preset.
  #
  # @return [Boolean]
  def user_preset?
    user_id.present?
  end

  # Check if this preset has a valid provider.
  #
  # @return [Boolean]
  def has_valid_provider?
    llm_provider_id.present? && llm_provider.present?
  end

  # All known provider identifications from the schema.
  # Used to apply generation settings to all provider paths.
  PROVIDER_IDENTIFICATIONS = %w[
    openai anthropic gemini xai deepseek qwen openai_compatible
  ].freeze

  # Apply this preset's settings to a SpaceMembership.
  #
  # This updates the membership's settings with the preset's generation
  # and prompt settings, and optionally sets the LLM provider.
  #
  # Generation settings are applied to all provider paths (settings.llm.providers.{provider}.generation)
  # to ensure they take effect regardless of which provider is selected.
  #
  # If the preset's provider was deleted (nullified by foreign key),
  # the membership's provider is left unchanged.
  #
  # @param membership [SpaceMembership] the membership to update
  # @param apply_provider [Boolean] whether to apply the preset's provider
  # @return [SpaceMembership] the updated membership
  def apply_to(membership, apply_provider: true)
    # Convert current settings to hash for manipulation
    current_settings = membership.settings
    new_settings = current_settings.respond_to?(:to_h) ? current_settings.to_h.deep_stringify_keys : (current_settings || {}).deep_dup

    # Initialize providers structure if needed
    new_settings["llm"] ||= {}
    new_settings["llm"]["providers"] ||= {}

    # Convert Schema objects to Hashes for merging
    gen_settings_hash = generation_settings_as_hash
    preset_settings_hash = preset_settings_as_hash

    # Apply generation settings to all provider paths
    PROVIDER_IDENTIFICATIONS.each do |provider|
      new_settings["llm"]["providers"][provider] ||= {}
      new_settings["llm"]["providers"][provider]["generation"] ||= {}
      new_settings["llm"]["providers"][provider]["generation"].merge!(gen_settings_hash)
    end

    # Apply preset settings under "preset" key
    new_settings["preset"] = (new_settings["preset"] || {}).merge(preset_settings_hash)

    attrs = { settings: new_settings, preset_id: id }

    # Only apply provider if it still exists (has_valid_provider? checks both ID and association)
    attrs[:llm_provider_id] = llm_provider_id if apply_provider && has_valid_provider?

    membership.update!(attrs)
    membership
  end

  # Convert generation_settings to a Hash (handles both Schema and Hash).
  #
  # @return [Hash] generation settings as hash with string keys
  def generation_settings_as_hash
    obj = generation_settings
    hash = obj.respond_to?(:to_h) ? obj.to_h : (obj || {})
    hash.deep_stringify_keys
  end

  # Convert preset_settings to a Hash (handles both Schema and Hash).
  #
  # @return [Hash] preset settings as hash with string keys
  def preset_settings_as_hash
    obj = preset_settings
    hash = obj.respond_to?(:to_h) ? obj.to_h : (obj || {})
    hash.deep_stringify_keys
  end

  # Create a new preset from a SpaceMembership's current settings.
  #
  # @param membership [SpaceMembership] the membership to snapshot
  # @param name [String] the name for the new preset
  # @param user [User, nil] the owner (nil for system preset)
  # @param description [String, nil] optional description
  # @return [Preset] the created preset
  def self.create_from_membership(membership, name:, user: nil, description: nil)
    settings = membership.settings
    settings_hash = settings.respond_to?(:to_h) ? settings.to_h.deep_stringify_keys : (settings || {})
    generation_settings_data = extract_generation_settings(membership, settings_hash)

    # Access preset settings from Schema object or Hash
    preset_settings_data = if settings.respond_to?(:preset)
      ps = settings.preset
      ps.respond_to?(:to_h) ? ps.to_h.deep_stringify_keys : (ps || {})
    else
      settings_hash["preset"] || {}
    end

    create(
      name: name,
      description: description,
      user: user,
      llm_provider_id: membership.llm_provider_id,
      generation_settings: generation_settings_data,
      preset_settings: preset_settings_data
    )
  end

  # Update this preset from a SpaceMembership's current settings.
  #
  # @param membership [SpaceMembership] the membership to snapshot
  # @return [Boolean] true if update succeeded, false otherwise
  def update_from_membership(membership)
    settings = membership.settings
    settings_hash = settings.respond_to?(:to_h) ? settings.to_h.deep_stringify_keys : (settings || {})
    generation_settings_data = self.class.extract_generation_settings(membership, settings_hash)

    # Access preset settings from Schema object or Hash
    preset_settings_data = if settings.respond_to?(:preset)
      ps = settings.preset
      ps.respond_to?(:to_h) ? ps.to_h.deep_stringify_keys : (ps || {})
    else
      settings_hash["preset"] || {}
    end

    update(
      llm_provider_id: membership.llm_provider_id,
      generation_settings: generation_settings_data,
      preset_settings: preset_settings_data
    )
  end

  # Extract generation settings from a membership's settings.
  # Looks under the current provider's path first, falls back to first available provider.
  #
  # @param membership [SpaceMembership] the membership
  # @param settings [Hash] the settings hash
  # @return [Hash] generation settings
  def self.extract_generation_settings(membership, settings)
    providers = settings.dig("llm", "providers") || {}

    # Try current provider first
    current_provider = membership.provider_identification
    if current_provider && providers.dig(current_provider, "generation").present?
      return providers.dig(current_provider, "generation").slice(
        "max_context_tokens", "max_response_tokens", "temperature",
        "top_p", "top_k", "repetition_penalty"
      )
    end

    # Fall back to first provider with generation settings
    PROVIDER_IDENTIFICATIONS.each do |provider|
      gen_settings = providers.dig(provider, "generation")
      next unless gen_settings.present?

      return gen_settings.slice(
        "max_context_tokens", "max_response_tokens", "temperature",
        "top_p", "top_k", "repetition_penalty"
      )
    end

    # Return empty hash if no generation settings found
    {}
  end
end
