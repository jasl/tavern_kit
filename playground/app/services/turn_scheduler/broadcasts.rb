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
        Instrumentation.profile("Broadcasts.queue_updated", conversation_id: conversation.id, space_id: conversation.space_id) do
          space = conversation.space
          is_group = space.group?

          render_seq = nil
          if is_group
            conversation.increment!(:group_queue_revision)
            render_seq = conversation.group_queue_revision
          end

          presenter = GroupQueuePresenter.new(conversation: conversation, space: space)

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

          payload = {
            type: "conversation_queue_updated",
            conversation_id: conversation.id,
            scheduling_state: presenter.scheduling_state,
            queue: queue_data,
          }
          payload[:group_queue_revision] = render_seq if render_seq

          ConversationChannel.broadcast_to(conversation, payload)

          # Broadcast Turbo Stream to update the queue UI (group chats only)
          if is_group
            Turbo::StreamsChannel.broadcast_replace_to(
              conversation, :messages,
              target: presenter.dom_id,
              partial: "messages/group_queue",
              locals: {
                presenter: presenter,
                render_seq: render_seq,
              }
            )
          end
        end
      end
    end
  end
end
