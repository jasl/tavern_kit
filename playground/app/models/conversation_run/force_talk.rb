# frozen_string_literal: true

# Force a specific character to speak (manual selection).
#
# Triggered when user manually selects a character to speak,
# bypassing the normal turn order. Used for:
# - "Talk" button in character picker
# - Manual character selection in group chats
#
# ## Execution
#
# Same as AutoTurn, but:
# - Ignores turn order (speaks immediately)
# - Does not decrement copilot steps (user initiated)
#
class ConversationRun::ForceTalk < ConversationRun
  # Always executes via RunExecutor
  def should_execute?
    true
  end
end
