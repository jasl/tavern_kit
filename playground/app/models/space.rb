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
  STATUSES = %w[active archived deleting].freeze
  REPLY_ORDERS = %w[manual natural list pooled].freeze
  CARD_HANDLING_MODES = %w[swap append append_disabled].freeze
  DURING_GENERATION_USER_INPUT_POLICIES = %w[queue restart reject].freeze

  has_many :conversations, dependent: :destroy

  has_many :space_memberships, dependent: :destroy do
    def grant_to(actors, **options)
      space = proxy_association.owner
      next_position = maximum(:position) || -1

      Array(actors).each do |actor|
        membership =
          if actor.is_a?(User)
            find_or_initialize_by(user_id: actor.id, kind: "human")
          else
            find_or_initialize_by(character_id: actor.id, kind: "character")
          end

        attrs = {}

        if membership.new_record? || membership.removed_membership?
          next_position += 1
          attrs[:position] = next_position
        end

        # Restore active status and participation
        attrs[:status] = "active"
        attrs[:participation] = "active"
        attrs[:removed_at] = nil
        attrs[:removed_by] = nil
        attrs[:removed_reason] = nil

        attrs[:persona] = options[:persona] if options.key?(:persona)
        attrs[:copilot_mode] = options[:copilot_mode] if options.key?(:copilot_mode)
        attrs[:role] = options[:role] if options.key?(:role)

        membership.assign_attributes(attrs)
        membership.save! if membership.changed?
      end
    end

    def revoke_from(actors, by_user: nil, reason: nil)
      Array(actors).each do |actor|
        membership =
          if actor.is_a?(User)
            find_by(user: actor)
          else
            find_by(character: actor)
          end

        membership&.remove!(by_user: by_user, reason: reason)
      end
    end

    def revise(granted: [], revoked: [], by_user: nil, reason: nil)
      transaction do
        grant_to(granted) if granted.present?
        revoke_from(revoked, by_user: by_user, reason: reason) if revoked.present?
      end
    end
  end

  has_many :active_space_memberships, -> { active }, class_name: "SpaceMembership"
  has_many :users, through: :active_space_memberships

  has_many :character_space_memberships,
           -> { active.where(kind: "character").where(user_id: nil).where.not(character_id: nil) },
           class_name: "SpaceMembership"
  has_many :characters, through: :character_space_memberships

  belongs_to :owner, class_name: "User"

  normalizes :name, with: ->(value) { value&.strip.presence }

  enum :status, STATUSES.index_by(&:itself), default: "active"
  enum :reply_order, REPLY_ORDERS.index_by(&:itself), default: "natural"
  enum :card_handling_mode, CARD_HANDLING_MODES.index_by(&:itself), default: "swap"
  enum :during_generation_user_input_policy,
       DURING_GENERATION_USER_INPUT_POLICIES.index_by(&:itself),
       default: "queue",
       prefix: true

  validates :name, presence: { message: "must contain visible characters" }
  validates :status, inclusion: { in: STATUSES }
  validates :reply_order, inclusion: { in: REPLY_ORDERS }
  validates :card_handling_mode, inclusion: { in: CARD_HANDLING_MODES }
  validates :during_generation_user_input_policy, inclusion: { in: DURING_GENERATION_USER_INPUT_POLICIES }
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
      "ORDER BY messages.created_at DESC, messages.id DESC LIMIT 1) AS last_message_content"
    )
  }

  class << self
    def create_for(attributes, user:, characters:)
      raise ArgumentError, "At least one character is required" if characters.blank?

      transaction do
        attrs = attributes.to_h.symbolize_keys

        attrs[:owner] = user
        attrs[:name] = default_name_for(characters) if attrs[:name].blank?

        create!(attrs).tap do |space|
          conversation = space.conversations.create!(title: "Main")
          space.space_memberships.grant_to([user, *characters])
          conversation.create_first_messages!
        end
      end
    end

    private

    def default_name_for(characters)
      names = Array(characters).filter_map(&:name).map(&:strip).compact_blank
      return "New Space" if names.empty?
      return names.first if names.size == 1

      names.join(", ").truncate(60)
    end
  end

  # STI type checking methods
  def playground?
    is_a?(Spaces::Playground)
  end

  def discussion?
    is_a?(Spaces::Discussion)
  end

  def group?
    space_memberships.count > 2
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
  # - Full copilot users with persona character (kind=human + user_id + character_id + copilot_mode=full)
  def ai_respondable_space_memberships
    space_memberships.participating.where(
      "(kind = 'character') OR " \
      "(kind = 'human' AND user_id IS NOT NULL AND character_id IS NOT NULL AND copilot_mode = ?)",
      "full"
    )
  end
end
