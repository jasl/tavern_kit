# frozen_string_literal: true

class ConversationEvent < ApplicationRecord
  validates :event_name, presence: true
  validates :conversation_id, presence: true
  validates :space_id, presence: true
  validates :occurred_at, presence: true

  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }
  scope :for_space, ->(space_id) { where(space_id: space_id) }
  scope :for_round, ->(round_id) { where(conversation_round_id: round_id) }
  scope :for_run, ->(run_id) { where(conversation_run_id: run_id) }
  scope :recent_first, -> { order(occurred_at: :desc, id: :desc) }

  def self.before(time)
    where("occurred_at < ?", time)
  end
end
