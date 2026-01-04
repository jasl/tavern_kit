# frozen_string_literal: true

# MessageSwipe represents a version of an AI response (swipe).
#
# A Message can have multiple swipes, allowing users to navigate between
# different AI-generated versions without changing the message's position
# in the conversation timeline.
#
# @example Create a swipe for a message
#   message.message_swipes.create!(position: 0, content: "First version")
#
# @example Navigate swipes
#   message.select_swipe!(direction: :right)
#
class MessageSwipe < ApplicationRecord
  belongs_to :message, counter_cache: true
  belongs_to :conversation_run, optional: true

  validates :position, presence: true,
                       numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :position, uniqueness: { scope: :message_id }

  scope :ordered, -> { order(:position) }

  # Check if this swipe is the active one for its message.
  #
  # @return [Boolean]
  def active?
    message.active_message_swipe_id == id
  end

  # Check if this is the first swipe (leftmost).
  #
  # @return [Boolean]
  def first?
    position.zero?
  end

  # Check if this is the last swipe (rightmost).
  #
  # @return [Boolean]
  def last?
    position == message.message_swipes.maximum(:position)
  end
end
