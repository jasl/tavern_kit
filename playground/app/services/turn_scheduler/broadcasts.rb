# frozen_string_literal: true

module TurnScheduler
  # Handles broadcasting queue updates to connected clients.
  #
  module Broadcasts
    class << self
      # Broadcasts a queue update to all connected clients.
      #
      # @param conversation [Conversation] the conversation to broadcast for
      def queue_updated(conversation)
        queue_members = Queries::QueuePreview.call(conversation: conversation, limit: 10)
        active_run = conversation.conversation_runs.active.includes(:speaker_space_membership).order(
          Arel.sql("CASE status WHEN 'running' THEN 0 WHEN 'queued' THEN 1 ELSE 2 END"),
          created_at: :desc
        ).first
        # Bullet may treat this include as "unused" in environments/tests where Turbo rendering is stubbed.
        # Touch the association so the eager load is semantically justified.
        active_run&.speaker_space_membership&.id

        # Broadcast JSON event for ActionCable listeners
        queue_data = queue_members.map do |member|
          {
            id: member.id,
            display_name: member.display_name,
            portrait_url: member.respond_to?(:portrait_url) ? member.portrait_url : nil,
          }
        end

        ConversationChannel.broadcast_to(
          conversation,
          type: "conversation_queue_updated",
          conversation_id: conversation.id,
          scheduling_state: conversation.scheduling_state,
          queue: queue_data
        )

        # Broadcast Turbo Stream to update the queue UI (group chats only)
        return unless conversation.space.group?

        Turbo::StreamsChannel.broadcast_replace_to(
          conversation, :messages,
          target: ActionView::RecordIdentifier.dom_id(conversation, :group_queue),
          partial: "messages/group_queue",
          locals: {
            conversation: conversation,
            space: conversation.space,
            queue_members: queue_members,
            active_run: active_run,
          }
        )
      end
    end
  end
end
