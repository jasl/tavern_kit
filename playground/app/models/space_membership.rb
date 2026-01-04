# frozen_string_literal: true

# SpaceMembership represents an identity within a Space.
#
# A membership can reference:
# - a human user (kind: human, user_id present)
# - an AI character (kind: character, character_id present, user_id nil)
# - a human user using a character persona (kind: human, user_id + character_id)
#
class SpaceMembership < ApplicationRecord
  include Portraitable

  KINDS = %w[human character].freeze
  ROLES = %w[owner member moderator].freeze
  COPILOT_MODES = %w[none full].freeze

  # Status (lifecycle): active member vs removed/kicked
  # Future: banned (cannot rejoin), archived (space archived)
  STATUSES = %w[active removed].freeze

  # Participation (involvement): controls AI speaker selection
  # - active: Full participant, included in speaker selection
  # - muted: Not auto-selected, but visible and can be manually triggered
  # - observer: Watch only (future multi-user spaces)
  PARTICIPATIONS = %w[active muted observer].freeze

  DEFAULT_COPILOT_STEPS = 5
  MAX_COPILOT_STEPS = 10

  belongs_to :space
  belongs_to :user, optional: true
  belongs_to :character, optional: true
  belongs_to :llm_provider, class_name: "LLMProvider", optional: true
  belongs_to :removed_by, class_name: "User", optional: true

  has_many :messages, dependent: :delete_all

  enum :kind, KINDS.index_by(&:itself), prefix: true
  enum :role, ROLES.index_by(&:itself), default: "member", prefix: true
  enum :copilot_mode, COPILOT_MODES.index_by(&:itself), default: "none", prefix: :copilot
  enum :status, STATUSES.index_by(&:itself), default: "active", suffix: :membership
  enum :participation, PARTICIPATIONS.index_by(&:itself), default: "active", prefix: :participation

  before_validation :normalize_copilot_remaining_steps
  before_create :cache_display_name
  before_destroy :prevent_direct_destroy

  validates :kind, inclusion: { in: KINDS }
  validates :role, inclusion: { in: ROLES }
  validates :copilot_mode, inclusion: { in: COPILOT_MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :participation, inclusion: { in: PARTICIPATIONS }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :copilot_remaining_steps,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_COPILOT_STEPS },
            allow_nil: true
  validates :copilot_remaining_steps, inclusion: { in: 1..MAX_COPILOT_STEPS }, if: :copilot_full?
  validate :kind_identity_matches_columns
  validate :copilot_requires_user_and_character
  validate :playground_space_allows_single_human_membership

  # Status-based scopes
  scope :active, -> { where(status: "active") }
  scope :removed, -> { where(status: "removed") }

  # Participation-based scopes (for speaker selection)
  scope :participating, -> { where(status: "active", participation: "active") }
  scope :muted, -> { where(participation: "muted") }

  scope :unread, -> { where.not(unread_at: nil) }
  scope :by_position, -> { order(:position) }
  scope :copilot_enabled, -> { where.not(copilot_mode: "none") }
  scope :moderators, -> { where(role: "moderator") }
  scope :with_ordered_space, -> { includes(:space).joins(:space).order("LOWER(spaces.name)") }
  scope :ai_characters, -> { where(kind: "character").where.not(character_id: nil).where(user_id: nil) }

  def display_name
    # Use cache first, fallback to live lookup for legacy data
    display_name_cache.presence || character&.name || user&.name || "[Deleted]"
  end

  def removed?
    removed_membership?
  end

  def effective_persona
    persona.presence || character&.personality
  end

  def to_participant
    return character.to_tavern_kit_character if character

    to_user_participant
  end

  def to_user_participant
    ::TavernKit::User.new(name: display_name, persona: effective_persona)
  end

  def character?
    character_id.present?
  end

  def ai_character?
    kind_character? && character_id.present? && user_id.blank?
  end

  def user?
    user_id.present?
  end

  def read
    update!(unread_at: nil)
  end

  def unread?
    unread_at.present?
  end

  def orphaned?
    user_id.nil? && character_id.nil?
  end

  def moderator?
    role_moderator?
  end

  def decrement_copilot_remaining_steps!
    return false unless user? && copilot_full?

    with_lock do
      return false unless user? && copilot_full?

      steps = copilot_remaining_steps.to_i
      new_steps = steps - 1

      if new_steps <= 0
        update!(copilot_remaining_steps: 0, copilot_mode: "none")
        Message::Broadcasts.broadcast_copilot_disabled(self, reason: "remaining_steps_exhausted")
      else
        update!(copilot_remaining_steps: new_steps)
        Message::Broadcasts.broadcast_copilot_steps_updated(self, remaining_steps: new_steps)
      end

      true
    end
  end

  def disable_copilot_mode!
    update!(copilot_mode: "none")
  end

  def can_auto_respond?
    return true if ai_character?
    return false unless copilot_full?

    copilot_remaining_steps.to_i > 0
  end

  def effective_llm_provider
    llm_provider || LLMProvider.get_default
  end

  def provider_identification
    effective_llm_provider&.identification
  end

  def llm_settings
    (settings || {}).fetch("llm", {})
  end

  # Remove this membership from the space.
  # Does NOT destroy the record - preserves it as an author anchor for messages.
  #
  # @param by_user [User, nil] the user who initiated the removal
  # @param reason [String, nil] optional reason for removal
  # @return [Boolean] true if update succeeded
  def remove!(by_user: nil, reason: nil)
    update!(
      status: "removed",
      removed_at: Time.current,
      removed_by: by_user,
      removed_reason: reason,
      participation: "muted",
      copilot_mode: "none",
      unread_at: nil
    )
  end

  private

  def normalize_copilot_remaining_steps
    self.copilot_remaining_steps = copilot_remaining_steps.to_i

    if copilot_full?
      self.copilot_remaining_steps = DEFAULT_COPILOT_STEPS if copilot_remaining_steps <= 0
    end
  end

  def cache_display_name
    self.display_name_cache ||= character&.name || user&.name
  end

  # Prevent direct destruction of memberships to preserve author anchors.
  # Memberships can only be destroyed when the parent Space is destroyed.
  def prevent_direct_destroy
    return if destroyed_by_association

    raise ActiveRecord::RecordNotDestroyed,
          "SpaceMembership cannot be destroyed directly. Use remove! for soft removal."
  end

  def kind_identity_matches_columns
    if kind_human?
      errors.add(:user_id, "must be present for human memberships") if new_record? && user_id.blank?
    elsif kind_character?
      errors.add(:user_id, "must be blank for character memberships") if user_id.present?
      errors.add(:character_id, "must be present for character memberships") if new_record? && character_id.blank?
    end
  end

  def copilot_requires_user_and_character
    return if copilot_none?
    return if user_id.present? && character_id.present?

    errors.add(:copilot_mode, "requires both a user and a character")
  end

  def playground_space_allows_single_human_membership
    return unless space&.playground?
    return unless kind_human?

    existing =
      SpaceMembership
        .where(space_id: space_id, kind: "human")
        .where.not(id: id)
        .exists?

    return unless existing

    errors.add(:kind, "only one human membership is allowed in a playground space")
  end
end
