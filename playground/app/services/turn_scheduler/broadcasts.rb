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

          # In multi-process setups, ActionCable events can arrive out of order.
          # Use a monotonic DB-backed revision for ALL conversations (not just group chats)
          # so clients can ignore stale scheduling_state updates.
          #
          # Avoid a subtle multi-process race:
          #
          # If we do `UPDATE` then `SELECT` without holding a row lock, a concurrent updater can
          # increment between them, causing multiple broadcasts to carry the same revision.
          #
          # The client-side `revision <= last` guard would then drop one of the events, potentially
          # leaving the UI in a stale state (because ActionCable events can arrive out of order).
          render_seq =
            Conversation.transaction do
              Conversation.lock.where(id: conversation.id).pick(:id)
              Conversation.where(id: conversation.id)
                          .update_all("group_queue_revision = COALESCE(group_queue_revision, 0) + 1")
              Conversation.where(id: conversation.id).pick(:group_queue_revision)
            end

          presenter = GroupQueuePresenter.new(conversation: conversation, space: space)
          snapshot = presenter.snapshot

          # Broadcast JSON event for ActionCable listeners
          queue_data = presenter.queue_members.map do |member|
            {
              id: member.id,
              display_name: member.display_name,
              portrait_url: member.respond_to?(:portrait_url) ? member.portrait_url : nil,
            }
          end

          active_round = snapshot.active_round
          paused_reason =
            if active_round&.scheduling_state == "paused"
              active_round.metadata&.dig("paused_reason")
            end

          paused_speaker = presenter.paused? ? presenter.current_speaker : nil

          payload = {
            type: "conversation_queue_updated",
            conversation_id: conversation.id,
            scheduling_state: presenter.scheduling_state,
            queue: queue_data,
            during_generation_user_input_policy: space.during_generation_user_input_policy,
            reject_policy: space.during_generation_user_input_policy_reject?,
            paused_reason: paused_reason,
            paused_speaker_id: paused_speaker&.id,
            paused_speaker_name: paused_speaker&.display_name,
          }
          payload[:group_queue_revision] = render_seq

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

            # Broadcast Turbo Stream to update the Manage-round modal editor (if present).
            # This enables cross-tab/device state sync for the round queue editor.
            Turbo::StreamsChannel.broadcast_replace_to(
              conversation, :messages,
              target: "round_queue_editor",
              partial: "conversations/round_queue_editor",
              locals: {
                conversation: conversation,
                space: space,
                render_seq: render_seq,
                snapshot: snapshot,
              }
            )
          end
        end
      end
    end
  end
end
