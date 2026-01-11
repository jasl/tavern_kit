# frozen_string_literal: true

module TurnScheduler
  # Handles broadcasting queue updates to connected clients.
  #
  # This is the single source of truth for queue-related broadcasts.
  # All queue updates should go through this module.
  #
  module Broadcasts
    class << self
      # Broadcasts a queue update to all connected clients.
      #
      # @param conversation [Conversation] the conversation to broadcast for
      def queue_updated(conversation)
        presenter = GroupQueuePresenter.new(conversation: conversation, space: conversation.space)

        # Touch the association to justify eager load (Bullet warning prevention)
        presenter.active_run&.speaker_space_membership&.id

        # Broadcast JSON event for ActionCable listeners
        queue_data = presenter.queue_members.map do |member|
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
          scheduling_state: presenter.scheduling_state,
          queue: queue_data
        )

        # Broadcast Turbo Stream to update the queue UI (group chats only)
        return unless conversation.space.group?

        conversation.increment!(:group_queue_revision)

        Turbo::StreamsChannel.broadcast_replace_to(
          conversation, :messages,
          target: presenter.dom_id,
          partial: "messages/group_queue",
          locals: {
            presenter: presenter,
            render_seq: conversation.group_queue_revision,
          }
        )
      end
    end
  end
end
