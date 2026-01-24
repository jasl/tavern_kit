# frozen_string_literal: true

# SpaceMembership represents an identity within a Space.
#
# There are three distinct membership types:
#
# 1. **Pure Human** (`kind: human`, `user_id` present, `character_id` nil)
#    A regular user participating as themselves.
#    Can enable Auto with a custom persona.
#
# 2. **Human with Persona** (`kind: human`, `user_id` present, `character_id` present)
#    A user roleplaying as a character (enables Auto features).
#    Uses character's personality by default, can override with custom persona.
#
# 3. **AI Character** (`kind: character`, `character_id` present, `user_id` nil)
#    An autonomous AI character controlled by the system.
#
# Use predicate methods to check membership type:
# - `pure_human?` - human without persona character
# - `human_with_persona?` - human using a character persona
# - `ai_character?` - autonomous AI character
# - `human?` - any human (pure or with persona)
#
# Auto can be enabled for:
# - Humans with a character (uses character's personality)
# - Pure humans with a custom persona (uses persona field)
#
class SpaceMembership < ApplicationRecord
  include Portraitable

  # Serialize settings as ConversationSettings::ParticipantSettings schema
  # This contains per-participant prompt building settings (LLM params, preset overrides, etc.)
  serialize :settings, coder: EasyTalkCoder.new(ConversationSettings::ParticipantSettings)

  KINDS = %w[human character].freeze
  ROLES = %w[owner member moderator].freeze
  AUTO_VALUES = %w[none auto].freeze

  # Status (lifecycle): active member vs removed/kicked
  # Future: banned (cannot rejoin), archived (space archived)
  STATUSES = %w[active removed].freeze

  # Participation (involvement): controls AI speaker selection
  # - active: Full participant, included in speaker selection
  # - muted: Not auto-selected, but visible and can be manually triggered
  # - observer: Watch only (future multi-user spaces)
  PARTICIPATIONS = %w[active muted observer].freeze

  DEFAULT_AUTO_STEPS = 1
  MAX_AUTO_STEPS = 10
  DEFAULT_TALKATIVENESS_FACTOR = 0.5

  belongs_to :space
  belongs_to :user, optional: true
  belongs_to :character, optional: true
  belongs_to :llm_provider, class_name: "LLMProvider", optional: true
  belongs_to :preset, optional: true
  belongs_to :removed_by, class_name: "User", optional: true

  # Use restrict_with_error to protect author anchors - memberships with messages cannot be destroyed.
  # Use remove! for soft removal instead of destroy.
  has_many :messages, dependent: :restrict_with_error

  enum :kind, KINDS.index_by(&:itself), prefix: true
  enum :role, ROLES.index_by(&:itself), default: "member", prefix: true
  enum :auto, AUTO_VALUES.index_by(&:itself), default: "none", prefix: :auto_setting
  enum :status, STATUSES.index_by(&:itself), default: "active", suffix: :membership
  enum :participation, PARTICIPATIONS.index_by(&:itself), default: "active", prefix: :participation

  before_validation :normalize_auto_remaining_steps
  before_save :update_cached_display_name
  before_destroy :prevent_direct_destroy
  after_commit :notify_scheduler_if_participation_changed, on: %i[create update]

  validates :kind, inclusion: { in: KINDS }
  validates :role, inclusion: { in: ROLES }
  validates :auto, inclusion: { in: AUTO_VALUES }
  validates :status, inclusion: { in: STATUSES }
  validates :participation, inclusion: { in: PARTICIPATIONS }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: false }
  validates :auto_remaining_steps,
           numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_AUTO_STEPS },
            allow_nil: true
  validates :auto_remaining_steps, inclusion: { in: 1..MAX_AUTO_STEPS }, if: :auto_enabled?
  validates :talkativeness_factor,
            numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 },
            allow_nil: true
  # Uniqueness validations - prevent duplicate memberships
  # Note: DB has unique index on (space_id, character_id) which catches edge cases
  validates :character_id,
            uniqueness: { scope: :space_id, message: "is already a member of this space" },
            if: -> { character_id.present? && kind_character? }
  validates :user_id,
            uniqueness: { scope: :space_id, message: "is already a member of this space" },
            if: -> { user_id.present? }
  validate :kind_identity_matches_columns
  validate :playground_space_allows_single_human_membership

  # Status-based scopes
  scope :active, -> { where(status: "active") }
  scope :removed, -> { where(status: "removed") }

  # Participation-based scopes (for speaker selection)
  scope :participating, -> { where(status: "active", participation: "active") }
  scope :muted, -> { where(participation: "muted") }

  scope :unread, -> { where.not(unread_at: nil) }
  scope :by_position, -> { order(:position) }
  scope :moderators, -> { where(role: "moderator") }
  scope :with_ordered_space, -> { includes(:space).joins(:space).order("LOWER(spaces.name)") }

  # AI characters: kind=character guarantees user_id is nil and character_id is present (via validation)
  scope :ai_characters, -> { kind_character }

  # Human memberships (both pure and with persona)
  scope :humans, -> { kind_human }

  def display_name
    # Use cache first, fallback to live lookup when cache is missing.
    cached_display_name.presence || character&.name || user&.name || "[Deleted]"
  end

  # Effective talkativeness used for group activation/sorting.
  #
  # ST parity: if the character card provides `data.extensions.talkativeness`, it
  # should drive talkativeness-based activation. We still allow per-membership
  # overrides by honoring `talkativeness_factor` when it is explicitly set.
  #
  # @return [Float]
  def effective_talkativeness_factor
    # Precedence:
    # 1) Per-membership override (if present)
    # 2) Character card talkativeness (AI characters only)
    # 3) Default
    override = talkativeness_factor
    return override.to_f unless override.nil?

    if kind_character? && character&.data&.talkativeness?
      return character.data.talkativeness_factor(default: DEFAULT_TALKATIVENESS_FACTOR).to_f
    end

    DEFAULT_TALKATIVENESS_FACTOR
  end

  def removed?
    removed_membership?
  end

  def effective_persona
    persona.presence || character&.personality
  end

  # ──────────────────────────────────────────────────────────────────
  # Membership type predicates
  # ──────────────────────────────────────────────────────────────────

  # True if this is a human membership (with or without persona).
  def human?
    kind_human?
  end

  # True if this is a human without a character persona.
  def pure_human?
    kind_human? && character_id.blank?
  end

  # True if this is a human using a character persona.
  def human_with_persona?
    kind_human? && character_id.present?
  end

  # True if this is a human that can use Auto mode.
  # All human memberships are Auto-capable (persona is optional).
  def auto_capable?
    kind_human?
  end

  # @return [Boolean] true if Auto is enabled (regardless of remaining steps)
  def auto_enabled?
    auto_setting_auto?
  end

  # @return [Boolean] true if Auto is disabled
  def auto_none?
    auto_setting_none?
  end

  # True if this is an autonomous AI character (not a human with persona).
  # Validation guarantees: kind=character => user_id nil, character_id present.
  def ai_character?
    kind_character?
  end

  # ──────────────────────────────────────────────────────────────────
  # Column presence predicates (lower-level, prefer type predicates above)
  # ──────────────────────────────────────────────────────────────────

  # True if character_id is present (both AI characters and humans with persona).
  def character?
    character_id.present?
  end

  # True if user_id is present (all human memberships).
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

  # Decrements the auto remaining steps atomically.
  #
  # Uses UPDATE with WHERE conditions to ensure atomic decrement without
  # pessimistic locking. The SQL ensures we only decrement if:
  # - This is a user membership (not AI)
  # - auto is "auto"
  # - auto_remaining_steps > 0
  #
  # If the counter reaches 0, auto mode is disabled.
  #
  # @return [Boolean] true if successfully decremented, false if conditions not met
  def decrement_auto_remaining_steps!
    SpaceMemberships::AutoStepsDecrementer.execute(membership: self)
  end

  def disable_auto!
    update!(auto: "none", auto_remaining_steps: nil)
  end

  def can_auto_respond?
    # Must be active (not removed) to auto-respond
    return false unless active_membership?

    return true if ai_character?
    return false unless auto_enabled?

    auto_remaining_steps.to_i > 0
  end

  # Whether this member can be auto-scheduled by the turn scheduler.
  # More restrictive than can_auto_respond? - also checks participation status.
  # Used by TurnScheduler to filter out muted members when advancing turns.
  def can_be_scheduled?
    participation_active? && can_auto_respond?
  end

  def effective_llm_provider
    return llm_provider if llm_provider&.enabled?

    preferred = space&.preferred_llm_provider
    return preferred if preferred&.enabled?

    LLMProvider.get_default
  end

  def provider_identification
    effective_llm_provider&.identification || provider_identification_from_settings
  end

  def llm_settings
    # Settings is now a ConversationSettings::ParticipantSettings schema object
    # Return as deeply stringified hash for compatibility with existing code that uses string keys
    settings&.llm&.to_h&.deep_stringify_keys || {}
  end

  def provider_identification_from_settings
    providers = llm_settings["providers"]
    return nil unless providers.is_a?(Hash)

    return "openai_compatible" if providers.key?("openai_compatible")

    providers.keys.sort.first
  end

  # ──────────────────────────────────────────────────────────────────
  # Author's Note Settings
  # ──────────────────────────────────────────────────────────────────

  # Get the character AN position mode (replace, before, after).
  # This determines how character AN combines with space AN.
  #
  # @return [String]
  def character_authors_note_position
    settings&.preset&.respond_to?(:character_authors_note_position) &&
      settings.preset.character_authors_note_position.presence ||
      character&.character_authors_note_position ||
      "replace"
  end

  # Check if the character's Author's Note should be used.
  #
  # @return [Boolean]
  def use_character_authors_note?
    # Check SM override first - PresetSettings doesn't have this field,
    # so fall back to character setting
    character&.authors_note_enabled? || false
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
      auto: "none",
      auto_remaining_steps: nil,
      unread_at: nil
    )
  end

  private

  def normalize_auto_remaining_steps
    # Check if user explicitly set steps BEFORE we modify the value (to_i would trigger changed?)
    user_set_steps = auto_remaining_steps_changed?

    unless auto_enabled?
      self.auto_remaining_steps = nil
      return
    end

    self.auto_remaining_steps = auto_remaining_steps.to_i

    # When enabling Auto mode, reset to default steps ONLY if the user
    # didn't explicitly set a steps value. This ensures:
    # - Clicking "Auto" button resets to DEFAULT_AUTO_STEPS each time
    # - API calls with explicit steps values are validated (may fail if > MAX)
    if auto_changed? && !user_set_steps
      self.auto_remaining_steps = DEFAULT_AUTO_STEPS
    end
    # Note: We do NOT auto-reset when steps reach 0 without mode change.
    # The AutoStepsDecrementer handles disabling auto when steps are exhausted.
  end

  # Update cached_display_name when character_id changes or on create.
  # Priority: character name > user name
  # This ensures human memberships with persona use the character's name for display.
  def update_cached_display_name
    # Always update if character_id changed (persona assigned/changed)
    # On create, set if not already set
    if character_id_changed? || new_record?
      self.cached_display_name = character&.name || user&.name
    end
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

  # Notify TurnScheduler when membership changes affect speaker selection.
  #
  # Changes that affect the turn queue:
  # - New member joins (create)
  # - Participation status changes (active ↔ muted)
  # - Auto changes (none ↔ auto)
  # - Status changes (active ↔ removed)
  #
  # This ensures the UI updates to reflect the new turn order.
  def notify_scheduler_if_participation_changed
    # Skip if space is not loaded (edge case during cleanup)
    return unless space

    # Check if any scheduling-relevant attributes changed
    relevant_changes = previous_changes.keys & %w[participation auto status]
    return if relevant_changes.empty? && !previously_new_record?

    should_skip_if_current_speaker = !previously_new_record? && !can_be_scheduled? && relevant_changes.any?

    # Notify all conversations in this space.
    #
    # For "active → not schedulable" transitions (remove/mute/disable auto),
    # auto-skip if this member is currently the scheduled speaker (P0: avoid stuck).
    space.conversations.find_each do |conversation|
      state = TurnScheduler.state(conversation)

      # If the scheduler is explicitly paused, do NOT auto-advance the round.
      # The next speaker will be re-evaluated on ResumeRound.
      if state.paused?
        TurnScheduler::Broadcasts.queue_updated(conversation)
        next
      end

      advanced =
        if should_skip_if_current_speaker && state.current_speaker_id == id
          TurnScheduler::Commands::SkipCurrentSpeaker.execute(
            conversation: conversation,
            speaker_id: id,
            reason: "membership_changed",
            cancel_running: true
          ).payload[:advanced]
        else
          false
        end

      TurnScheduler::Broadcasts.queue_updated(conversation) unless advanced
    end
  end
end
