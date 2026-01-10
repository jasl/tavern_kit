# frozen_string_literal: true

# AI character automatically responding in conversation.
#
# This is the most common run type - triggered when:
# - User sends a message → AI responds
# - Auto mode schedules next speaker
# - Scheduler selects an AI character
#
# ## Execution
#
# Uses the standard RunExecutor flow:
# 1. Claim run (queued → running)
# 2. Build prompt via ContextBuilder
# 3. Call LLM
# 4. Create message with response
# 5. Finalize (succeeded/failed)
#
class ConversationRun::AutoTurn < ConversationRun
  # Always executes via RunExecutor
  def should_execute?
    true
  end
end
