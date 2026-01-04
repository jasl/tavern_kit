# frozen_string_literal: true

# ParticipantResolver provides a read-only view of SpaceMemberships relevant to a Conversation.
#
# Responsibilities:
# - Resolve ordered memberships (humans then characters).
# - Provide basic reply-order candidate ordering (manual/natural/list/pooled).
# - Provide character-membership sets for joined-card modes (include/exclude non-participating).
class ParticipantResolver
  REPLY_ORDERS = %w[manual natural list pooled].freeze
  # Support both legacy (muted) and new (non_participating) naming
  JOIN_MODES = %w[join_include_muted join_exclude_muted join_include_non_participating join_exclude_non_participating].freeze

  def initialize(conversation)
    @conversation = conversation
    @space = conversation.space
  end

  # Ordered memberships for UI / prompt context.
  #
  # Order:
  # 1) humans (by position)
  # 2) AI characters (by position)
  def ordered_memberships
    humans = space.space_memberships.where(kind: "human").order(:position, :id)
    characters = space.space_memberships.where(kind: "character").order(:position, :id)
    humans.to_a + characters.to_a
  end

  # Returns AI speaker candidates ordered according to reply_order.
  #
  # This is intentionally "basic": it provides an ordered pool, not full scheduling state.
  def ordered_ai_candidates(reply_order: space.reply_order)
    order = reply_order.to_s
    order = "natural" unless REPLY_ORDERS.include?(order)

    candidates = conversation.ai_respondable_participants.by_position.to_a.select(&:can_auto_respond?)

    case order
    when "manual"
      []
    when "pooled"
      candidates.shuffle
    else
      candidates
    end
  end

  # Character memberships to use for joined-card modes.
  #
  # join_include_*: include non-participating members
  # join_exclude_*: exclude non-participating members unless they are the speaker
  def character_memberships_for_join(mode:, speaker:)
    mode = mode.to_s
    mode = "join_exclude_non_participating" unless JOIN_MODES.include?(mode)

    memberships =
      space
        .space_memberships
        .where.not(character_id: nil)
        .by_position
        .includes(:character)
        .to_a

    if speaker&.character? && memberships.none? { |m| m.id == speaker.id }
      memberships << speaker
    end

    # Include all if mode is "include" variant
    return memberships if mode.include?("include")

    # Exclude non-participating unless they are the speaker
    memberships.select { |m| m.participation_active? || (speaker && m.id == speaker.id) }
  end

  private

  attr_reader :conversation, :space
end
