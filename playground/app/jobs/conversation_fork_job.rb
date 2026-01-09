# frozen_string_literal: true

# Background job for copying messages when forking a conversation.
#
# This job handles the potentially expensive operation of copying messages
# from a parent conversation to a newly created child conversation.
# For conversations with many messages, this prevents blocking the web request.
#
# @example Enqueue a fork operation
#   ConversationForkJob.perform_later(
#     child_conversation_id: child.id,
#     parent_conversation_id: parent.id,
#     fork_from_message_id: message.id
#   )
#
class ConversationForkJob < ApplicationJob
  queue_as :default

  # Retry on transient database errors
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  # Discard if conversation was deleted during processing
  discard_on ActiveRecord::RecordNotFound

  # Copy messages from parent conversation to child conversation.
  #
  # @param child_conversation_id [Integer] the newly created conversation
  # @param parent_conversation_id [Integer] the source conversation
  # @param fork_from_message_id [Integer] copy messages up to and including this
  def perform(child_conversation_id:, parent_conversation_id:, fork_from_message_id:)
    child_conversation = Conversation.find(child_conversation_id)
    parent_conversation = Conversation.find(parent_conversation_id)
    fork_from_message = Message.find(fork_from_message_id)

    # Skip if already processed
    return if child_conversation.ready?

    Conversation.transaction do
      clone_messages(child_conversation, parent_conversation, fork_from_message)
      child_conversation.mark_forking_complete!
    end

    # Broadcast completion to user
    broadcast_fork_complete(child_conversation)
  rescue StandardError => e
    # Mark as failed and broadcast error
    child_conversation = Conversation.find_by(id: child_conversation_id)
    if child_conversation&.pending?
      child_conversation.mark_forking_failed!(e.message)
      broadcast_fork_failed(child_conversation, e.message)
    end
    raise # Re-raise for retry mechanism
  end

  private

  # Clone messages from parent to child conversation.
  #
  # @param child_conversation [Conversation]
  # @param parent_conversation [Conversation]
  # @param fork_from_message [Message]
  def clone_messages(child_conversation, parent_conversation, fork_from_message)
    messages_to_clone = parent_conversation.messages
      .where("seq <= ?", fork_from_message.seq)
      .ordered
      .includes(:message_swipes, :active_message_swipe)

    messages_to_clone.each do |original_message|
      clone_message(child_conversation, original_message)
    end
  end

  # Clone a single message with its swipes.
  #
  # @param child_conversation [Conversation]
  # @param original_message [Message]
  def clone_message(child_conversation, original_message)
    cloned_message = child_conversation.messages.create!(
      space_membership_id: original_message.space_membership_id,
      seq: original_message.seq,
      role: original_message.role,
      content: original_message.content,
      metadata: original_message.metadata,
      excluded_from_prompt: original_message.excluded_from_prompt,
      origin_message_id: original_message.id
    )

    clone_swipes(cloned_message, original_message)
  end

  # Clone swipes for a message.
  #
  # @param cloned_message [Message]
  # @param original_message [Message]
  def clone_swipes(cloned_message, original_message)
    return if original_message.message_swipes.empty?

    cloned_swipes_by_position = {}

    original_message.message_swipes.each do |swipe|
      cloned_swipes_by_position[swipe.position] = cloned_message.message_swipes.create!(
        position: swipe.position,
        content: swipe.content,
        metadata: swipe.metadata
        # Note: conversation_run_id intentionally not copied (historical reference)
      )
    end

    # Set active swipe pointer if the original had one
    return unless original_message.active_message_swipe

    active_clone = cloned_swipes_by_position[original_message.active_message_swipe.position]
    cloned_message.update!(
      active_message_swipe: active_clone,
      content: active_clone.content
    )
  end

  # Broadcast fork completion to the user via Turbo Streams.
  #
  # @param conversation [Conversation]
  def broadcast_fork_complete(conversation)
    space = conversation.space
    return unless space

    conversation_url = Rails.application.routes.url_helpers.conversation_path(conversation)
    title = ERB::Util.html_escape(conversation.title)

    # Broadcast toast with clickable link (HTML in message)
    broadcast_toast_html(
      space,
      I18n.t(
        "conversations.fork.complete_html",
        default: "Branch ready: <a href='%{url}' class='link link-hover underline'>%{title}</a>",
        url: conversation_url,
        title: title
      ),
      :success
    )
  end

  # Broadcast fork failure notification.
  #
  # @param conversation [Conversation]
  # @param error [String]
  def broadcast_fork_failed(conversation, error)
    space = conversation.space
    return unless space

    broadcast_toast(
      space,
      I18n.t("conversations.fork.failed", default: "Branch creation failed: %{error}", error: error.truncate(100)),
      :error
    )
  end

  # Broadcast a toast notification via Turbo Streams.
  #
  # @param space [Space] the space to broadcast to
  # @param message [String] the notification message
  # @param type [Symbol] the notification type (:success, :error, :warning, :info)
  def broadcast_toast(space, message, type = :info)
    return unless space && message.present?

    Turbo::StreamsChannel.broadcast_action_to(
      space,
      action: :show_toast,
      target: nil,
      partial: "shared/toast",
      locals: { message: message, type: type }
    )
  end

  # Broadcast a toast notification with HTML content via JavaScript event.
  # Used for toasts that need clickable links.
  #
  # @param space [Space] the space to broadcast to
  # @param html_message [String] the HTML message (already escaped)
  # @param type [Symbol] the notification type
  def broadcast_toast_html(space, html_message, type = :info)
    return unless space && html_message.present?

    # Use append_all to inject a script that triggers the toast event
    # This is the same pattern used by the checkpoint controller
    Turbo::StreamsChannel.broadcast_append_to(
      space,
      target: "body",
      html: <<~HTML
        <script data-turbo-temporary>
          window.dispatchEvent(new CustomEvent("toast:show", {
            detail: {
              message: #{html_message.to_json},
              type: "#{type}",
              duration: 5000,
              html: true
            },
            bubbles: true,
            cancelable: true
          }));
        </script>
      HTML
    )
  end
end
