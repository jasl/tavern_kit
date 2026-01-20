# frozen_string_literal: true

# Guard service for enforcing tail-only mutations on conversation messages.
#
# Any operation that rewrites existing timeline content (edit, regenerate, switch swipes)
# can only be performed on the tail (last) message. To modify earlier content, use
# "Branch from here" to create a new timeline.
#
# Note: user-visible "delete message" is implemented as a soft delete (`visibility="hidden"`)
# and is intentionally NOT guarded by this service.
#
# @example Check if a message is the tail
#   guard = TailMutationGuard.new(conversation)
#   guard.tail?(message) # => true/false
#
# @example Get the tail message ID for frontend
#   guard.tail_message_id # => 123 or nil
#
class TailMutationGuard
  attr_reader :conversation

  # @param conversation [Conversation] the conversation to guard
  def initialize(conversation)
    @conversation = conversation
  end

  # Returns the tail (last) message in the conversation.
  #
  # @return [Message, nil] the last message by seq, or nil if empty
  def tail_message
    @tail_message ||= conversation.messages.ui_visible.order(seq: :desc, id: :desc).first
  end

  # Returns the ID of the tail message.
  #
  # @return [Integer, nil] the tail message ID, or nil if no messages
  def tail_message_id
    tail_message&.id
  end

  # Check if the given message is the tail (last) message.
  #
  # @param message [Message] the message to check
  # @return [Boolean] true if the message is the tail
  def tail?(message)
    message.id == tail_message_id
  end
end
