# frozen_string_literal: true

class ConversationRoundParticipant < ApplicationRecord
  STATUSES = %w[pending spoken skipped].freeze

  belongs_to :conversation_round
  belongs_to :space_membership

  enum :status, STATUSES.index_by(&:itself), default: "pending"

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }
end
