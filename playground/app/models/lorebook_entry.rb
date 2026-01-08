# frozen_string_literal: true

# A single entry within a Lorebook (World Info entry).
#
# Entries are activated during prompt generation when their keywords
# are matched in the scan buffer. Activated entries inject their content
# into the prompt at the configured position.
#
class LorebookEntry < ApplicationRecord
  # Valid insertion positions (matching TavernKit::Lore::Entry::POSITIONS)
  POSITIONS = %w[
    before_char_defs after_char_defs before_example_messages after_example_messages
    top_of_an bottom_of_an at_depth outlet
  ].freeze

  # Valid selective logic options
  SELECTIVE_LOGIC = %w[and_any and_all not_any not_all].freeze

  # Valid roles
  ROLES = %w[system user assistant].freeze

  # Associations
  belongs_to :lorebook, inverse_of: :entries, counter_cache: false

  delegate :locked_at, :locked?, to: :lorebook, allow_nil: true

  # Validations
  validates :uid, presence: true, uniqueness: { scope: :lorebook_id }
  validates :position, inclusion: { in: POSITIONS }
  validates :selective_logic, inclusion: { in: SELECTIVE_LOGIC }
  validates :role, inclusion: { in: ROLES }
  validates :insertion_order, numericality: { only_integer: true }
  validates :depth, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :probability, numericality: { in: 0..100 }
  validates :group_weight, numericality: { only_integer: true, greater_than: 0 }

  validate :lorebook_must_not_be_locked, on: %i[create update]

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :constant, -> { where(constant: true) }
  scope :ordered, -> { order(:position_index, :insertion_order) }
  scope :by_insertion_order, -> { order(insertion_order: :desc) }

  # Callbacks
  before_validation :generate_uid, on: :create
  before_create :set_position_index
  before_destroy :prevent_destroy_when_lorebook_locked

  # Convert to TavernKit::Lore::Entry for prompt building.
  #
  # @param source [Symbol] source identifier
  # @param book_name [String] parent book name
  # @return [TavernKit::Lore::Entry]
  def to_lore_entry(source: :global, book_name: nil)
    TavernKit::Lore::Entry.new(
      uid: uid,
      keys: keys || [],
      content: content.to_s,
      secondary_keys: secondary_keys || [],
      selective: selective,
      selective_logic: selective_logic&.to_sym || :and_any,
      enabled: enabled,
      constant: constant,
      insertion_order: insertion_order,
      position: position&.to_sym || :after_char_defs,
      depth: depth,
      role: role&.to_sym || :system,
      outlet: outlet,
      triggers: (triggers || []).map(&:to_sym),
      scan_depth: scan_depth,
      source: source,
      book_name: book_name || lorebook&.name,
      comment: comment,
      match_persona_description: match_persona_description,
      match_character_description: match_character_description,
      match_character_personality: match_character_personality,
      match_character_depth_prompt: match_character_depth_prompt,
      match_scenario: match_scenario,
      match_creator_notes: match_creator_notes,
      ignore_budget: ignore_budget,
      use_probability: use_probability,
      probability: probability,
      group: group,
      group_override: group_override,
      group_weight: group_weight,
      use_group_scoring: use_group_scoring,
      automation_id: automation_id,
      sticky: sticky,
      cooldown: cooldown,
      delay: delay,
      exclude_recursion: exclude_recursion,
      prevent_recursion: prevent_recursion,
      delay_until_recursion: delay_until_recursion,
      # CCv3: use_regex and case_sensitive are now passed directly
      use_regex: use_regex,
      case_sensitive: case_sensitive
    )
  end

  # Export to SillyTavern-compatible JSON hash.
  #
  # @return [Hash]
  def export_to_json
    {
      uid: uid,
      key: keys || [],
      keysecondary: secondary_keys || [],
      content: content,
      comment: comment,
      enabled: enabled,
      constant: constant,
      order: insertion_order,
      position: position_to_st_number,
      depth: depth,
      role: role_to_st_number,
      selectiveLogic: selective_logic_to_st_number,
      selective: selective,
      probability: probability,
      useProbability: use_probability,
      group: group,
      groupWeight: group_weight,
      groupOverride: group_override,
      useGroupScoring: use_group_scoring,
      sticky: sticky,
      cooldown: cooldown,
      delay: delay,
      excludeRecursion: exclude_recursion,
      preventRecursion: prevent_recursion,
      delayUntilRecursion: delay_until_recursion,
      scanDepth: scan_depth,
      useRegex: use_regex,
      caseSensitive: case_sensitive,
      matchWholeWords: match_whole_words,
      matchPersonaDescription: match_persona_description,
      matchCharacterDescription: match_character_description,
      matchCharacterPersonality: match_character_personality,
      matchCharacterDepthPrompt: match_character_depth_prompt,
      matchScenario: match_scenario,
      matchCreatorNotes: match_creator_notes,
      ignoreBudget: ignore_budget,
      automationId: automation_id,
    }.compact
  end

  # Build attributes hash from ST World Info JSON entry.
  #
  # @param data [Hash] entry data
  # @param uid [String] entry UID
  # @param position_index [Integer] position index for ordering
  # @return [Hash]
  def self.attributes_from_json(data, uid:, position_index: 0)
    data = data.with_indifferent_access

    {
      uid: uid,
      comment: data[:comment] || data[:memo] || data[:name],
      keys: parse_keys(data[:key] || data[:keys]),
      secondary_keys: parse_keys(data[:keysecondary] || data[:secondary_keys]),
      content: data[:content],
      enabled: coerce_bool(data[:enabled], default: true),
      constant: coerce_bool(data[:constant]),
      insertion_order: data[:order] || data[:insertion_order] || data[:priority] || 100,
      position: position_from_st(data[:position] || data[:pos]),
      depth: data[:depth] || data[:insert_depth] || 4,
      role: role_from_st(data[:role] || data[:depth_role]),
      outlet: data[:outlet] || data[:outlet_name] || data[:outletName],
      selective: coerce_bool(data[:selective]),
      selective_logic: selective_logic_from_st(data[:selectiveLogic] || data[:selective_logic]),
      probability: data[:probability] || 100,
      use_probability: coerce_bool(data[:useProbability] || data[:use_probability], default: true),
      group: data[:group],
      group_weight: data[:groupWeight] || data[:group_weight] || 100,
      group_override: coerce_bool(data[:groupOverride] || data[:group_override]),
      use_group_scoring: coerce_bool_nil(data[:useGroupScoring] || data[:use_group_scoring]),
      sticky: positive_int(data[:sticky]),
      cooldown: positive_int(data[:cooldown]),
      delay: positive_int(data[:delay]),
      exclude_recursion: coerce_bool(data[:excludeRecursion] || data[:exclude_recursion]),
      prevent_recursion: coerce_bool(data[:preventRecursion] || data[:prevent_recursion]),
      delay_until_recursion: coerce_delay_until_recursion(data[:delayUntilRecursion] || data[:delay_until_recursion]),
      scan_depth: positive_int(data[:scanDepth] || data[:scan_depth]),
      use_regex: coerce_bool(data[:useRegex] || data[:use_regex]),
      case_sensitive: coerce_bool_nil(data[:caseSensitive] || data[:case_sensitive]),
      match_whole_words: coerce_bool_nil(data[:matchWholeWords] || data[:match_whole_words]),
      match_persona_description: coerce_bool(data[:matchPersonaDescription] || data[:match_persona_description]),
      match_character_description: coerce_bool(data[:matchCharacterDescription] || data[:match_character_description]),
      match_character_personality: coerce_bool(data[:matchCharacterPersonality] || data[:match_character_personality]),
      match_character_depth_prompt: coerce_bool(data[:matchCharacterDepthPrompt] || data[:match_character_depth_prompt]),
      match_scenario: coerce_bool(data[:matchScenario] || data[:match_scenario]),
      match_creator_notes: coerce_bool(data[:matchCreatorNotes] || data[:match_creator_notes]),
      ignore_budget: coerce_bool(data[:ignoreBudget] || data[:ignore_budget]),
      triggers: parse_triggers(data[:triggers]),
      automation_id: data[:automationId] || data[:automation_id],
      position_index: position_index,
    }
  end

  # Display name (comment or truncated keys)
  def display_name
    comment.presence || keys&.first(3)&.join(", ")&.truncate(50) || "Entry #{uid}"
  end

  private

  def generate_uid
    self.uid ||= SecureRandom.uuid
  end

  def set_position_index
    max_index = lorebook&.entries&.maximum(:position_index) || -1
    self.position_index = max_index + 1
  end

  def lorebook_must_not_be_locked
    return unless lorebook&.locked?

    errors.add(:base, "Lorebook is locked")
  end

  def prevent_destroy_when_lorebook_locked
    return unless lorebook&.locked?

    errors.add(:base, "Lorebook is locked")
    throw :abort
  end

  # ST position number mapping
  POSITION_MAP = {
    0 => "before_char_defs", 1 => "after_char_defs", 2 => "top_of_an", 3 => "bottom_of_an",
    4 => "at_depth", 5 => "before_example_messages", 6 => "after_example_messages", 7 => "outlet",
  }.freeze

  POSITION_REVERSE_MAP = POSITION_MAP.invert.freeze

  def position_to_st_number
    POSITION_REVERSE_MAP[position] || 1
  end

  def self.position_from_st(value)
    return "after_char_defs" if value.nil?
    return value.to_s if POSITIONS.include?(value.to_s)

    POSITION_MAP[value.to_i] || "after_char_defs"
  end

  # ST role number mapping
  ROLE_MAP = { 0 => "system", 1 => "user", 2 => "assistant" }.freeze
  ROLE_REVERSE_MAP = ROLE_MAP.invert.freeze

  def role_to_st_number
    ROLE_REVERSE_MAP[role] || 0
  end

  def self.role_from_st(value)
    return "system" if value.nil?
    return value.to_s if ROLES.include?(value.to_s)

    ROLE_MAP[value.to_i] || "system"
  end

  # ST selective logic mapping
  SELECTIVE_LOGIC_MAP = { 0 => "and_any", 1 => "not_all", 2 => "not_any", 3 => "and_all" }.freeze
  SELECTIVE_LOGIC_REVERSE_MAP = SELECTIVE_LOGIC_MAP.invert.freeze

  def selective_logic_to_st_number
    SELECTIVE_LOGIC_REVERSE_MAP[selective_logic] || 0
  end

  def self.selective_logic_from_st(value)
    return "and_any" if value.nil?
    return value.to_s if SELECTIVE_LOGIC.include?(value.to_s)

    SELECTIVE_LOGIC_MAP[value.to_i] || "and_any"
  end

  def self.parse_keys(value)
    case value
    when Array then value.map(&:to_s).reject(&:empty?)
    when String then TavernKit::Lore::KeyList.parse(value)
    else []
    end
  end

  def self.parse_triggers(value)
    return [] if value.nil?

    Array(value).map(&:to_s).reject(&:empty?)
  end

  def self.coerce_bool(value, default: false)
    return default if value.nil?
    return value if value == true || value == false

    %w[1 true yes y on].include?(value.to_s.strip.downcase)
  end

  def self.coerce_bool_nil(value)
    return nil if value.nil?

    coerce_bool(value)
  end

  def self.positive_int(value)
    return nil if value.nil?

    i = value.to_i
    i.positive? ? i : nil
  end

  # Coerce delay_until_recursion value from ST format.
  # ST stores this as: false (disabled), true (level 1), or integer (specific level).
  def self.coerce_delay_until_recursion(value)
    return nil if value.nil?
    return nil if value == false || value == 0 || value.to_s.strip.downcase == "false"
    return 1 if value == true || value.to_s.strip.downcase == "true"

    level = value.to_i
    level.positive? ? level : nil
  end
end
