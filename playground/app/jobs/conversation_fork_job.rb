# frozen_string_literal: true

# Background job for copying messages when forking a conversation.
#
# This job handles the potentially expensive operation of copying messages
# from a parent conversation to a newly created child conversation.
# For conversations with many messages, this prevents blocking the web request.
#
# Uses Copy-on-Write (COW) for efficient content sharing:
# - Messages and swipes share TextContent records via text_content_id
# - No content is duplicated; only references are created
# - TextContent reference counts are incremented atomically
#
# Uses batch insertion for performance:
# - Messages are inserted in bulk using insert_all
# - Swipes are inserted in bulk using insert_all
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
      batch_clone_messages(child_conversation, parent_conversation, fork_from_message)
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

  # Batch clone messages using insert_all for performance.
  # Reuses text_content_id for COW content sharing.
  #
  # @param child_conversation [Conversation] the target conversation
  # @param parent_conversation [Conversation] the source conversation
  # @param fork_from_message [Message] copy up to and including this message
  def batch_clone_messages(child_conversation, parent_conversation, fork_from_message)
    messages_to_clone = parent_conversation.messages
      .scheduler_visible
      .where("seq <= ?", fork_from_message.seq)
      .ordered
      .includes(:message_swipes, :active_message_swipe, :message_attachments)

    return if messages_to_clone.empty?

    now = Time.current

    # Build message data for batch insert (COW: reuse text_content_id)
    message_data = messages_to_clone.map do |m|
      {
        conversation_id: child_conversation.id,
        space_membership_id: m.space_membership_id,
        text_content_id: m.text_content_id,
        content: m.read_attribute(:content), # Keep content column in sync (denormalized copy)
        seq: m.seq,
        role: m.role,
        metadata: m.metadata || {},
        visibility: m.visibility,
        origin_message_id: m.id,
        message_swipes_count: m.message_swipes_count,
        created_at: now,
        updated_at: now,
      }
    end

    # Batch insert messages
    Message.insert_all(message_data)

    # Build origin_message_id -> new_message mapping
    new_messages = child_conversation.messages.index_by(&:origin_message_id)

    # Collect text_content_ids for reference count update
    message_text_content_ids = messages_to_clone.filter_map(&:text_content_id)

    # Batch clone swipes
    swipe_text_content_ids = batch_clone_swipes(messages_to_clone, new_messages, now)

    # Update active_message_swipe pointers
    update_active_swipe_pointers(messages_to_clone, new_messages)

    # Batch clone attachments (reuse blob)
    batch_clone_attachments(messages_to_clone, new_messages, now)

    # Batch increment TextContent references (tally handles duplicates correctly)
    all_text_content_ids = (message_text_content_ids + swipe_text_content_ids).compact
    TextContent.batch_increment_references!(all_text_content_ids) if all_text_content_ids.any?

    # Reset association cache so subsequent queries reflect database state
    child_conversation.messages.reset
  end

  # Batch clone swipes for all messages.
  #
  # @param messages_to_clone [Array<Message>] original messages
  # @param new_messages [Hash<Integer, Message>] origin_message_id -> new message mapping
  # @param now [Time] timestamp
  # @return [Array<Integer>] text_content_ids for reference counting
  def batch_clone_swipes(messages_to_clone, new_messages, now)
    swipe_data = []
    text_content_ids = []

    messages_to_clone.each do |original_message|
      new_message = new_messages[original_message.id]
      next unless new_message

      original_message.message_swipes.each do |swipe|
        text_content_ids << swipe.text_content_id if swipe.text_content_id

        swipe_data << {
          message_id: new_message.id,
          text_content_id: swipe.text_content_id,
          content: swipe.read_attribute(:content),
          position: swipe.position,
          metadata: swipe.metadata || {},
          created_at: now,
          updated_at: now,
        }
      end
    end

    MessageSwipe.insert_all(swipe_data) if swipe_data.any?

    text_content_ids
  end

  # Update active_message_swipe pointers for cloned messages.
  #
  # @param messages_to_clone [Array<Message>] original messages
  # @param new_messages [Hash<Integer, Message>] origin_message_id -> new message mapping
  def update_active_swipe_pointers(messages_to_clone, new_messages)
    # Build a mapping of new_message_id -> active_swipe_position
    swipe_positions = {}

    messages_to_clone.each do |original_message|
      next unless original_message.active_message_swipe

      new_message = new_messages[original_message.id]
      next unless new_message

      swipe_positions[new_message.id] = original_message.active_message_swipe.position
    end

    return if swipe_positions.empty?

    # Query the new swipes directly from database (not cached in memory)
    new_swipes = MessageSwipe.where(message_id: swipe_positions.keys)
                             .index_by { |s| [s.message_id, s.position] }

    # Build and execute updates
    swipe_positions.each do |message_id, position|
      swipe = new_swipes[[message_id, position]]
      next unless swipe

      Message.where(id: message_id).update_all(active_message_swipe_id: swipe.id)
    end
  end

  # Batch clone attachments for all messages (reuse blobs).
  #
  # @param messages_to_clone [Array<Message>] original messages
  # @param new_messages [Hash<Integer, Message>] origin_message_id -> new message mapping
  # @param now [Time] timestamp
  def batch_clone_attachments(messages_to_clone, new_messages, now)
    attachment_data = []

    messages_to_clone.each do |original_message|
      new_message = new_messages[original_message.id]
      next unless new_message

      original_message.message_attachments.each do |attachment|
        attachment_data << {
          message_id: new_message.id,
          blob_id: attachment.blob_id, # Reuse blob
          name: attachment.name,
          position: attachment.position,
          kind: attachment.kind,
          metadata: attachment.metadata || {},
          created_at: now,
          updated_at: now,
        }
      end
    end

    MessageAttachment.insert_all(attachment_data) if attachment_data.any?
  end

  # Broadcast fork completion to the user via Turbo Streams.
  #
  # @param conversation [Conversation]
  def broadcast_fork_complete(conversation)
    space = conversation.space
    return unless space

    conversation_path = Rails.application.routes.url_helpers.conversation_path(conversation)
    url = ERB::Util.html_escape(conversation_path)
    title = ERB::Util.html_escape(conversation.title)

    html_message = I18n.t(
      "conversations.fork.complete_html",
      default: "Branch ready: <a href='%{url}' class='link link-hover underline'>%{title}</a>",
      url: url,
      title: title
    )

    broadcast_toast(space, html_message.html_safe, :success)
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
end
