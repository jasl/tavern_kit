# frozen_string_literal: true

module ConversationEvents
  module Queries
    class EventStream
      DEFAULT_LIMIT = 50
      MAX_LIMIT = 500

      VALID_SCOPES = %w[all scheduler run].freeze

      def self.execute(
        conversation:,
        limit: DEFAULT_LIMIT,
        conversation_round_id: nil,
        conversation_run_id: nil,
        scope: "all"
      )
        limit = limit.to_i
        limit = DEFAULT_LIMIT if limit <= 0
        limit = MAX_LIMIT if limit > MAX_LIMIT

        scope_name = scope.to_s
        scope_name = "all" unless VALID_SCOPES.include?(scope_name)

        relation = ConversationEvent.for_conversation(conversation.id)
        relation = relation.for_round(conversation_round_id) if conversation_round_id.present?
        relation = relation.for_run(conversation_run_id) if conversation_run_id.present?

        relation =
          case scope_name
          when "scheduler"
            relation.where("event_name LIKE ?", "turn_scheduler.%")
          when "run"
            relation.where("event_name LIKE ?", "conversation_run.%")
          else
            relation
          end

        relation.recent_first.limit(limit)
      end
    end
  end
end
