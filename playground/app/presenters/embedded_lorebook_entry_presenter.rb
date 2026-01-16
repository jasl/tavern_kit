# frozen_string_literal: true

# Presenter for displaying and editing embedded lorebook entries (character_book.entries).
#
# Wraps Hash entries from the character's embedded character_book JSON with
# a consistent interface matching LorebookEntry, plus path helpers for CRUD operations.
#
# @example
#   entry = character.character_book.entries.first
#   presenter = EmbeddedLorebookEntryPresenter.new(entry, character: character, mode: :settings)
#   presenter.display_name  # => "eldoria"
#   presenter.edit_path     # => "/settings/characters/2/embedded_lorebook_entries/entry-1/edit"
#
class EmbeddedLorebookEntryPresenter
  include Rails.application.routes.url_helpers

  attr_reader :entry, :character, :mode

  def initialize(entry, character:, mode: :public)
    @entry = entry.is_a?(Hash) ? entry.with_indifferent_access : entry
    @character = character
    @mode = mode
  end

  # ────────────────────────────────────────────────────────────────────────────
  # Identity
  # ────────────────────────────────────────────────────────────────────────────

  def id
    fetch(:id)&.to_s
  end

  def display_name
    (fetch(:comment).presence || fetch(:name).presence || keys.first(3).join(", ").presence || "Entry #{id}").to_s
  end

  # ────────────────────────────────────────────────────────────────────────────
  # Status
  # ────────────────────────────────────────────────────────────────────────────

  def enabled?
    value = fetch(:enabled)
    value.nil? ? true : value == true
  end

  def constant?
    fetch(:constant) == true
  end

  def use_regex?
    fetch(:use_regex) == true
  end

  def selective?
    fetch(:selective) == true && secondary_keys.any?
  end

  # ────────────────────────────────────────────────────────────────────────────
  # Keys & Content
  # ────────────────────────────────────────────────────────────────────────────

  def keys
    Array(fetch(:keys)).map(&:to_s)
  end

  def secondary_keys
    Array(fetch(:secondary_keys)).map(&:to_s)
  end

  def content
    fetch(:content).to_s
  end

  def comment
    fetch(:comment)
  end

  # ────────────────────────────────────────────────────────────────────────────
  # Insertion Settings
  # ────────────────────────────────────────────────────────────────────────────

  def position
    fetch(:position)&.to_s || "before_char_defs"
  end

  def insertion_order
    fetch(:insertion_order) || 100
  end

  def depth
    fetch(:depth) || 4
  end

  def role
    fetch(:role)&.to_s || "system"
  end

  def outlet
    fetch(:outlet)
  end

  def selective_logic
    fetch(:selective_logic)&.to_s || "and_any"
  end

  # ────────────────────────────────────────────────────────────────────────────
  # Advanced Settings
  # ────────────────────────────────────────────────────────────────────────────

  def probability
    fetch(:probability) || 100
  end

  def use_probability
    fetch(:use_probability) != false
  end

  def group
    fetch(:group)
  end

  def group_weight
    fetch(:group_weight) || 100
  end

  def group_override
    fetch(:group_override) == true
  end

  def use_group_scoring
    fetch(:use_group_scoring)
  end

  def sticky
    fetch(:sticky)
  end

  def cooldown
    fetch(:cooldown)
  end

  def delay
    fetch(:delay)
  end

  def exclude_recursion
    fetch(:exclude_recursion) == true
  end

  def prevent_recursion
    fetch(:prevent_recursion) == true
  end

  def delay_until_recursion
    fetch(:delay_until_recursion)
  end

  def scan_depth
    fetch(:scan_depth)
  end

  def case_sensitive
    fetch(:case_sensitive)
  end

  def match_whole_words
    fetch(:match_whole_words)
  end

  def match_persona_description
    fetch(:match_persona_description) == true
  end

  def match_character_description
    fetch(:match_character_description) == true
  end

  def match_character_personality
    fetch(:match_character_personality) == true
  end

  def match_character_depth_prompt
    fetch(:match_character_depth_prompt) == true
  end

  def match_scenario
    fetch(:match_scenario) == true
  end

  def match_creator_notes
    fetch(:match_creator_notes) == true
  end

  def ignore_budget
    fetch(:ignore_budget) == true
  end

  def automation_id
    fetch(:automation_id)
  end

  # ────────────────────────────────────────────────────────────────────────────
  # Mode Helpers
  # ────────────────────────────────────────────────────────────────────────────

  def settings_mode?
    mode == :settings
  end

  def editable?
    !character.locked?
  end

  # ────────────────────────────────────────────────────────────────────────────
  # Path Helpers
  # ────────────────────────────────────────────────────────────────────────────

  def index_path
    settings_mode? ? settings_character_embedded_lorebook_entries_path(character) : character_embedded_lorebook_entries_path(character)
  end

  def edit_path
    settings_mode? ? edit_settings_character_embedded_lorebook_entry_path(character, id) : edit_character_embedded_lorebook_entry_path(character, id)
  end

  def update_path
    settings_mode? ? settings_character_embedded_lorebook_entry_path(character, id) : character_embedded_lorebook_entry_path(character, id)
  end

  def destroy_path
    settings_mode? ? settings_character_embedded_lorebook_entry_path(character, id) : character_embedded_lorebook_entry_path(character, id)
  end

  # ────────────────────────────────────────────────────────────────────────────
  # View Helpers
  # ────────────────────────────────────────────────────────────────────────────

  def dom_id
    "embedded_lorebook_entry_#{id}"
  end

  # Convert to hash for form building
  def to_form_hash
    {
      id: id,
      comment: comment,
      keys: keys,
      secondary_keys: secondary_keys,
      content: content,
      enabled: enabled?,
      constant: constant?,
      use_regex: use_regex?,
      selective: selective?,
      selective_logic: selective_logic,
      position: position,
      insertion_order: insertion_order,
      depth: depth,
      role: role,
      outlet: outlet,
      probability: probability,
      use_probability: use_probability,
      group: group,
      group_weight: group_weight,
      group_override: group_override,
      use_group_scoring: use_group_scoring,
      sticky: sticky,
      cooldown: cooldown,
      delay: delay,
      exclude_recursion: exclude_recursion,
      prevent_recursion: prevent_recursion,
      delay_until_recursion: delay_until_recursion,
      scan_depth: scan_depth,
      case_sensitive: case_sensitive,
      match_whole_words: match_whole_words,
      match_persona_description: match_persona_description,
      match_character_description: match_character_description,
      match_character_personality: match_character_personality,
      match_character_depth_prompt: match_character_depth_prompt,
      match_scenario: match_scenario,
      match_creator_notes: match_creator_notes,
      ignore_budget: ignore_budget,
      automation_id: automation_id,
    }
  end

  private

  def fetch(key)
    if @entry.is_a?(Hash) || @entry.respond_to?(:[])
      @entry[key] || @entry[key.to_s]
    elsif @entry.respond_to?(key)
      @entry.public_send(key)
    end
  end
end
