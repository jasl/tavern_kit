# frozen_string_literal: true

# Service object for creating conversation branches (forks).
#
# Implements SillyTavern-style branching: "Create Branch = clone chat up to a message and switch to it"
#
# Uses Copy-on-Write (COW) for efficient content sharing:
# - Messages and swipes share TextContent records via text_content_id
# - No content is duplicated during fork; only references are created
# - Content is only copied when edited (handled by Message/MessageSwipe models)
#
# Uses batch insertion for performance:
# - Messages are inserted in bulk using insert_all
# - Swipes are inserted in bulk using insert_all
# - TextContent reference counts are updated atomically
#
# Supports two modes:
# - Synchronous (async: false): Copies messages immediately. Good for short conversations.
# - Asynchronous (async: true): Creates conversation with pending status, enqueues job to copy.
#   Good for long conversations to avoid blocking web requests.
#
# @example Create a branch synchronously
#   result = Conversations::Forker.new(
#     parent_conversation: conversation,
#     fork_from_message: message,
#     kind: "branch",
#     title: "My Branch"
#   ).call
#
#   if result.success?
#     redirect_to result.conversation
#   end
#
# @example Create a branch asynchronously
#   result = Conversations::Forker.new(
#     parent_conversation: conversation,
#     fork_from_message: message,
#     kind: "branch",
#     async: true
#   ).call
#
#   if result.success?
#     # Conversation created but messages still copying
#     # User will be notified via Turbo broadcast when complete
#   end
#
class Conversations::Forker
  Result = Data.define(:success?, :conversation, :error, :error_code, :async?) do
    def ok? = success?
  end

  # Threshold for automatic async mode (number of messages)
  AUTO_ASYNC_THRESHOLD = 50

  # @param parent_conversation [Conversation] The conversation to fork from
  # @param fork_from_message [Message] The message to fork at (inclusive)
  # @param kind [String] "branch", "thread", or "checkpoint"
  # @param title [String, nil] Title for the new conversation
  # @param visibility [String] "shared" or "private"
  # @param async [Boolean, nil] Force async mode. If nil, auto-detect based on message count.
  def initialize(parent_conversation:, fork_from_message:, kind:, title: nil, visibility: nil, async: nil)
    @parent_conversation = parent_conversation
    @fork_from_message = fork_from_message
    @kind = kind
    @title = title.presence || default_title
    @visibility = visibility.presence || "shared"
    @async = async
  end

  # Execute the fork operation.
  #
  # @return [Result] Result object with success?, conversation, error, and async? flag
  def call
    validate!

    use_async = should_use_async?
    child_conversation = nil

    if use_async
      # Async mode: create conversation with pending status, enqueue job
      Conversation.transaction do
        child_conversation = create_child_conversation(status: "pending")
      end

      ConversationForkJob.perform_later(
        child_conversation_id: child_conversation.id,
        parent_conversation_id: parent_conversation.id,
        fork_from_message_id: fork_from_message.id
      )

      Result.new(success?: true, conversation: child_conversation, error: nil, error_code: nil, async?: true)
    else
      # Sync mode: copy messages immediately using batch insert
      Conversation.transaction do
        child_conversation = create_child_conversation
        batch_clone_messages(child_conversation)
      end

      Result.new(success?: true, conversation: child_conversation, error: nil, error_code: nil, async?: false)
    end
  rescue ValidationError => e
    Result.new(success?: false, conversation: nil, error: e.message, error_code: :validation_failed, async?: false)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, conversation: nil, error: e.record.errors.full_messages.to_sentence, error_code: :validation_failed, async?: false)
  rescue ActiveRecord::InvalidForeignKey
    # FK violation: fork_from_message was deleted concurrently
    Result.new(success?: false, conversation: nil, error: "The conversation has changed. Please reload and try again.", error_code: :conversation_changed, async?: false)
  rescue ActiveRecord::RecordNotFound
    # Message or related record deleted during cloning
    Result.new(success?: false, conversation: nil, error: "The conversation has changed. Please reload and try again.", error_code: :conversation_changed, async?: false)
  end

  private

  attr_reader :parent_conversation, :fork_from_message, :kind, :title, :visibility, :async

  # Determine whether to use async mode.
  #
  # @return [Boolean]
  def should_use_async?
    return async unless async.nil?

    # Auto-detect: use async if message count exceeds threshold
    messages_to_copy_count > AUTO_ASYNC_THRESHOLD
  end

  # Count messages that will be copied (for auto-async detection).
  #
  # @return [Integer]
  def messages_to_copy_count
    parent_conversation.messages.scheduler_visible.where("seq <= ?", fork_from_message.seq).count
  end

  class ValidationError < StandardError; end

  def validate!
    validate_space_type!
    validate_message_belongs_to_conversation!
  end

  def validate_space_type!
    return if kind == "thread" # threads allowed in all spaces

    # branches only allowed in Playground (solo) spaces
    unless parent_conversation.space.playground?
      raise ValidationError, "Branching is only allowed in Playground spaces"
    end
  end

  def validate_message_belongs_to_conversation!
    return if fork_from_message.conversation_id == parent_conversation.id

    raise ValidationError, "Message does not belong to the parent conversation"
  end

  def create_child_conversation(status: "ready")
    parent_conversation.space.conversations.create!(
      title: title,
      kind: kind,
      visibility: visibility,
      parent_conversation: parent_conversation,
      forked_from_message: fork_from_message,
      authors_note: parent_conversation.authors_note,
      status: status
    )
  end

  # Batch clone messages using insert_all for performance.
  # Reuses text_content_id for COW content sharing.
  #
  # @param child_conversation [Conversation] the target conversation
  def batch_clone_messages(child_conversation)
    messages_to_clone = parent_conversation.messages
      .scheduler_visible
      .where("seq <= ?", fork_from_message.seq)
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
        # active_message_swipe_id will be set after swipes are cloned
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
  # @param now [Time] timestamp for created_at/updated_at
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
          content: swipe.read_attribute(:content), # Keep content column in sync (denormalized copy)
          position: swipe.position,
          metadata: swipe.metadata || {},
          created_at: now,
          updated_at: now,
          # Note: conversation_run_id intentionally not copied (historical reference)
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

  def default_title
    "Branch"
  end
end
