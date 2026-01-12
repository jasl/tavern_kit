# frozen_string_literal: true

class ConversationRound < ApplicationRecord
  STATUSES = %w[active finished superseded canceled].freeze
  SCHEDULING_STATES = %w[ai_generating paused failed].freeze

  belongs_to :conversation
  belongs_to :trigger_message, class_name: "Message", optional: true

  has_many :participants, class_name: "ConversationRoundParticipant",
                          dependent: :delete_all,
                          inverse_of: :conversation_round

  enum :status, STATUSES.index_by(&:itself)

  validates :status, inclusion: { in: STATUSES }
  validates :scheduling_state, inclusion: { in: SCHEDULING_STATES }, allow_nil: true
  validates :current_position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
