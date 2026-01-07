# frozen_string_literal: true

# Locates the active "full copilot" user in a Space (if any).
#
# Used by both followup planning and error handling to avoid duplicating
# the selection predicate.
#
class Conversations::RunExecutor::CopilotUserFinder
  def self.find_active(space)
    space.space_memberships.active.find do |m|
      m.user? && m.copilot_full? && m.can_auto_respond?
    end
  end
end
