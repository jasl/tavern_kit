# frozen_string_literal: true

# Regenerate an existing AI message (create a new swipe).
#
# Triggered when user clicks "Regenerate" on an AI message.
# Instead of creating a new message, adds a new swipe to the
# existing message.
#
# ## Execution
#
# 1. Find target message from debug.target_message_id
# 2. Build prompt with message excluded (before_message)
# 3. Call LLM
# 4. Add new swipe to target message
# 5. Set new swipe as active
#
class ConversationRun::Regenerate < ConversationRun
  # Always executes via RunExecutor
  def should_execute?
    true
  end

  # Get the target message to regenerate.
  #
  # @return [Message, nil]
  def target_message
    return @target_message if defined?(@target_message)

    target_id = debug&.dig("target_message_id")
    @target_message = conversation&.messages&.find_by(id: target_id)
  end
end
