# frozen_string_literal: true

# Space model for organizing chat participants and defaults.
#
# Design notes:
# - Space stores permissions, participants, and default settings.
# - Message timeline lives in Conversations.
# - Runtime execution state lives in ConversationRuns.
#
# STI subclasses:
# - Spaces::Playground (solo roleplay: one human + AI characters)
# - Spaces::Discussion (multi-user chat: multiple humans + AI characters)
#
class Space < ApplicationRecord
  include Publishable

  # Use settings_version for optimistic locking to prevent lost updates.
  self.locking_column = :settings_version

  # Serialize prompt_settings as ConversationSettings::SpaceSettings schema
  # This contains only prompt-building related settings
  serialize :prompt_settings, coder: EasyTalkCoder.new(ConversationSettings::SpaceSettings)

  STATUSES = %w[active archived deleting].freeze
  VISIBILITIES = %w[private public].freeze
  REPLY_ORDERS = %w[manual natural list pooled].freeze
  CARD_HANDLING_MODES = %w[swap append append_disabled].freeze
  DURING_GENERATION_USER_INPUT_POLICIES = %w[queue restart reject].freeze
  GROUP_REGENERATE_MODES = %w[single_message last_turn].freeze

  has_many :conversations, dependent: :destroy
  has_many :space_lorebooks, dependent: :destroy
  has_many :lorebooks, through: :space_lorebooks

  has_many :space_memberships, dependent: :destroy do
    # Convenience wrappers for membership lifecycle operations.
    # Business logic lives in app/services/space_memberships/*.

    def grant_to(actors, **options)
      SpaceMemberships::Grant.call(space: proxy_association.owner, actors: actors, **options)
    end

    def revoke_from(actors, by_user: nil, reason: nil)
      SpaceMemberships::Revoke.call(space: proxy_association.owner, actors: actors, by_user: by_user, reason: reason)
    end

    def revise(granted: [], revoked: [], by_user: nil, reason: nil)
      SpaceMemberships::Revise.call(space: proxy_association.owner, granted: granted, revoked: revoked, by_user: by_user, reason: reason)
    end
  end

  has_many :active_space_memberships, -> { active }, class_name: "SpaceMembership"
  has_many :users, through: :active_space_memberships

  # AI character memberships (excludes humans with personas)
  # Uses the simplified ai_characters scope from SpaceMembership
  has_many :character_space_memberships,
           -> { active.ai_characters },
           class_name: "SpaceMembership"
  has_many :characters, through: :character_space_memberships

  belongs_to :owner, class_name: "User"

  normalizes :name, with: ->(value) { value&.strip.presence }

  enum :status, STATUSES.index_by(&:itself), default: "active"
  enum :reply_order, REPLY_ORDERS.index_by(&:itself), default: "natural"
  enum :card_handling_mode, CARD_HANDLING_MODES.index_by(&:itself), default: "swap"
  enum :during_generation_user_input_policy,
       DURING_GENERATION_USER_INPUT_POLICIES.index_by(&:itself),
       default: "reject",
       prefix: true
  enum :group_regenerate_mode,
       GROUP_REGENERATE_MODES.index_by(&:itself),
       default: "single_message",
       prefix: true

  validates :name, presence: { message: "must contain visible characters" }
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }

  # Visibility enum
  enum :visibility, VISIBILITIES.index_by(&:itself), default: "private", suffix: :space
  validates :reply_order, inclusion: { in: REPLY_ORDERS }
  validates :card_handling_mode, inclusion: { in: CARD_HANDLING_MODES }
  validates :during_generation_user_input_policy, inclusion: { in: DURING_GENERATION_USER_INPUT_POLICIES }
  validates :group_regenerate_mode, inclusion: { in: GROUP_REGENERATE_MODES }
  validates :auto_mode_delay_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :user_turn_debounce_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # STI scopes
  scope :playgrounds, -> { where(type: "Spaces::Playground") }
  scope :discussions, -> { where(type: "Spaces::Discussion") }

  scope :ordered, -> { order("LOWER(name)") }

  scope :with_last_message_preview, lambda {
    select(
      "#{table_name}.*",
      "(SELECT messages.content FROM messages " \
      "INNER JOIN conversations ON conversations.id = messages.conversation_id " \
      "WHERE conversations.space_id = #{table_name}.id " \
      "ORDER BY messages.created_at DESC, messages.id DESC LIMIT 1) AS last_message_content",
      "(SELECT messages.created_at FROM messages " \
      "INNER JOIN conversations ON conversations.id = messages.conversation_id " \
      "WHERE conversations.space_id = #{table_name}.id " \
      "ORDER BY messages.created_at DESC, messages.id DESC LIMIT 1) AS last_message_at"
    )
  }

  # Sort by most recent activity (last message time, falling back to updated_at)
  # Uses inline subquery to avoid dependency on SELECT alias
  scope :by_recent_activity, lambda {
    order(Arel.sql(
            "COALESCE(" \
            "(SELECT messages.created_at FROM messages " \
            "INNER JOIN conversations ON conversations.id = messages.conversation_id " \
            "WHERE conversations.space_id = #{table_name}.id " \
            "ORDER BY messages.created_at DESC, messages.id DESC LIMIT 1), " \
            "#{table_name}.updated_at) DESC"
          ))
  }

  class << self
    def create_for(attributes, user:, characters:)
      ::Spaces::Creator.call(space_class: self, attributes: attributes, user: user, characters: characters)
    end

    def accessible_to(user)
      super(user, owner_column: :owner_id)
    end
  end

  # STI type checking methods
  def playground?
    is_a?(Spaces::Playground)
  end

  def discussion?
    is_a?(Spaces::Discussion)
  end

  # A space is a "group chat" when it has multiple active AI characters.
  # This aligns with SillyTavern's definition of group chat.
  def group?
    space_memberships.active.ai_characters.limit(2).count == 2
  end

  def archive!
    update!(status: "archived")
  end

  def unarchive!
    update!(status: "active")
  end

  def mark_deleting!
    update!(status: "deleting")
  end

  # Participants eligible to speak via automated generation.
  #
  # Includes:
  # - AI characters (kind=character) with active status and participation
  # - Full copilot users with persona character (kind=human + user_id + character_id + copilot_mode=full + copilot_remaining_steps > 0)
  #
  # Eager loads :character and :user to avoid N+1 queries in TurnScheduler.
  def ai_respondable_space_memberships
    space_memberships.participating.includes(:character, :user).where(
      "(kind = 'character') OR " \
      "(kind = 'human' AND user_id IS NOT NULL AND character_id IS NOT NULL AND copilot_mode = ? AND copilot_remaining_steps > 0)",
      "full"
    )
  end
end
