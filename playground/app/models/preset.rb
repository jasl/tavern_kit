# frozen_string_literal: true

# Preset stores reusable LLM settings configurations.
#
# Presets can be system-level (user_id = nil) or user-created.
# Each preset stores generation settings (temperature, top_p, etc.)
# and prompt settings (main_prompt, post_history_instructions, etc.).
#
# @example Get the default preset
#   Preset.get_default
#   # => #<Preset name: "Default", ...> (or nil if not configured)
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
  include Duplicatable
  include Lockable
  include Publishable

  # Serialize jsonb columns as structured Schema objects
  # Reuse ConversationSettings schemas to avoid duplication
  serialize :generation_settings, coder: EasyTalkCoder.new(ConversationSettings::LLM::GenerationSettings)
  serialize :preset_settings, coder: EasyTalkCoder.new(ConversationSettings::PresetSettings)

  belongs_to :llm_provider, optional: true
  belongs_to :user, optional: true

  has_many :space_memberships, dependent: :nullify

  # Visibility values
  VISIBILITIES = %w[private public].freeze

  validates :name, presence: true
  validates :visibility, inclusion: { in: VISIBILITIES }

  # Enums (use suffix to avoid conflict with Ruby's built-in private? method)
  enum :visibility, VISIBILITIES.index_by(&:itself), default: "private", suffix: true
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
    },
  }.freeze

  class << self
    def accessible_to(user)
      accessible_to_system_or_owned(user, owner_column: :user_id)
    end

    # Get the default preset.
    #
    # Returns the configured default preset (if set and exists).
    #
    # If no default is set (or the stored default points to a missing preset),
    # falls back to the first available preset by ID.
    #
    # Prefer a system preset (user_id=nil) for the fallback.
    # If no presets exist, returns nil.
    #
    # This method does not seed presets or auto-persist fallbacks.
    #
    # @return [Preset, nil] the default preset (or nil if none exist)
    def get_default
      preset_id = Setting.get("preset.default_id")
      if preset_id.is_a?(String) && preset_id.match?(/\A\d+\z/)
        preset_id = preset_id.to_i
      end

      if preset_id.is_a?(Integer)
        preset = find_by(id: preset_id)
        return preset if preset
      end

      system_presets.order(:id).first || order(:id).first
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
    # Called from db/seeds.rb.
    #
    # @return [Array<Preset>] created/updated presets
    def seed_system_presets!
      SYSTEM_PRESETS.map do |_key, config|
        find_or_create_by!(name: config[:name], user_id: nil) do |preset|
          preset.description = config[:description]
          preset.generation_settings = config[:generation_settings]
          preset.preset_settings = config[:preset_settings]
          preset.locked_at = Time.zone.now
        end
      end
    end

    # Get all presets for selection UI.
    #
    # @param user [User, nil] the user to include user presets for
    # @return [ActiveRecord::Relation] presets ordered for UI
    def for_select(user: nil)
      accessible_to(user).order(:user_id, :name)
    end

    private
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
    llm_provider_id.present? && llm_provider&.enabled?
  end

  # Returns the effective provider for display/usage.
  #
  # - If the preset points to an enabled provider, return it.
  # - If the preset points to a disabled provider, fall back to the default provider.
  # - If no provider is set (or it was nullified by FK), returns nil.
  #
  # @return [LLMProvider, nil]
  def effective_llm_provider
    return llm_provider if llm_provider&.enabled?
    return nil if llm_provider_id.blank?

    LLMProvider.get_default
  end

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
    Presets::MembershipApplier.call(preset: self, membership: membership, apply_provider: apply_provider)
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
    snapshot = Presets::MembershipSnapshot.build(membership: membership)

    create(
      name: name,
      description: description,
      user: user,
      llm_provider_id: membership.llm_provider_id,
      generation_settings: snapshot[:generation_settings],
      preset_settings: snapshot[:preset_settings]
    )
  end

  # Update this preset from a SpaceMembership's current settings.
  #
  # @param membership [SpaceMembership] the membership to snapshot
  # @return [Boolean] true if update succeeded, false otherwise
  def update_from_membership(membership)
    snapshot = Presets::MembershipSnapshot.build(membership: membership)

    update(
      llm_provider_id: membership.llm_provider_id,
      generation_settings: snapshot[:generation_settings],
      preset_settings: snapshot[:preset_settings]
    )
  end

  private

  # Attributes for creating a copy of this preset.
  # Used by Duplicatable concern.
  #
  # @return [Hash] attributes for the copy
  def copy_attributes
    {
      name: "#{name} (Copy)",
      description: description,
      llm_provider_id: llm_provider_id,
      generation_settings: generation_settings_as_hash,
      preset_settings: preset_settings_as_hash,
      visibility: "private",
      # Note: user_id is NOT copied - copies are always user-owned
      # Note: locked_at is NOT copied - copies start fresh
      # Note: visibility is explicitly set to private - copies start as drafts
    }
  end
end
