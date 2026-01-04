# frozen_string_literal: true

# Service object for creating conversation branches (forks).
#
# Implements SillyTavern-style branching: "Create Branch = clone chat up to a message and switch to it"
#
# @example Create a branch from a message
#   result = Conversation::Forker.new(
#     parent_conversation: conversation,
#     fork_from_message: message,
#     kind: "branch",
#     title: "My Branch"
#   ).call
#
#   if result.success?
#     redirect_to result.conversation
#   else
#     flash[:alert] = result.error
#   end
#
class Conversation::Forker
  Result = Data.define(:success?, :conversation, :error)

  # @param parent_conversation [Conversation] The conversation to fork from
  # @param fork_from_message [Message] The message to fork at (inclusive)
  # @param kind [String] "branch" or "thread"
  # @param title [String, nil] Title for the new conversation
  # @param visibility [String] "shared" or "private"
  def initialize(parent_conversation:, fork_from_message:, kind:, title: nil, visibility: nil)
    @parent_conversation = parent_conversation
    @fork_from_message = fork_from_message
    @kind = kind
    @title = title.presence || default_title
    @visibility = visibility.presence || "shared"
  end

  # Execute the fork operation.
  #
  # @return [Result] Result object with success?, conversation, and error
  def call
    validate!

    child_conversation = nil

    Conversation.transaction do
      child_conversation = create_child_conversation
      clone_messages(child_conversation)
    end

    Result.new(success?: true, conversation: child_conversation, error: nil)
  rescue ValidationError => e
    Result.new(success?: false, conversation: nil, error: e.message)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, conversation: nil, error: e.record.errors.full_messages.to_sentence)
  end

  private

  attr_reader :parent_conversation, :fork_from_message, :kind, :title, :visibility

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

  def create_child_conversation
    parent_conversation.space.conversations.create!(
      title: title,
      kind: kind,
      visibility: visibility,
      parent_conversation: parent_conversation,
      forked_from_message: fork_from_message
    )
  end

  def clone_messages(child_conversation)
    messages_to_clone = parent_conversation.messages
      .where("seq <= ?", fork_from_message.seq)
      .ordered
      .includes(:message_swipes, :active_message_swipe)

    messages_to_clone.each do |original_message|
      clone_message(child_conversation, original_message)
    end
  end

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

  def default_title
    "Branch"
  end
end
