# frozen_string_literal: true

# Conversation model for a message timeline inside a Space.
#
# Tree structure fields:
# - parent_conversation_id: direct parent (nullable for root)
# - root_conversation_id: the root of the tree (self for root conversations)
# - forked_from_message_id: the message in parent where this conversation branched from
#
class Conversation < ApplicationRecord
  include Publishable

  KINDS = %w[root branch thread checkpoint].freeze
  VISIBILITIES = %w[shared private public].freeze
  STATUSES = %w[ready pending failed archived].freeze

  # Scheduling states for the unified turn scheduler
  SCHEDULING_STATES = %w[idle round_active waiting_for_speaker ai_generating human_waiting failed].freeze

  # Auto-mode constants (conversation-level AI-to-AI dialogue)
  MAX_AUTO_MODE_ROUNDS = 10
  DEFAULT_AUTO_MODE_ROUNDS = 4

  # Cleanup before deleting messages.
  # IMPORTANT: These must be declared BEFORE has_many with dependent: :delete_all
  # because Rails processes callbacks in declaration order, and delete_all skips
  # individual record callbacks.
  before_destroy :delete_message_attachments
  before_destroy :decrement_text_content_references

  # Associations
  belongs_to :space
  belongs_to :parent_conversation, class_name: "Conversation", optional: true
  belongs_to :root_conversation, class_name: "Conversation", optional: true
  belongs_to :forked_from_message, class_name: "Message", optional: true, inverse_of: :forked_conversations
  belongs_to :current_speaker, class_name: "SpaceMembership", optional: true

  has_many :child_conversations, class_name: "Conversation",
                                 foreign_key: :parent_conversation_id,
                                 dependent: :destroy,
                                 inverse_of: :parent_conversation
  # Query-only association for finding all descendants in the tree.
  # Cleanup is handled by child_conversations dependent: :destroy (recursive).
  has_many :descendant_conversations, class_name: "Conversation",
                                      foreign_key: :root_conversation_id,
                                      inverse_of: :root_conversation

  has_many :conversation_runs, dependent: :delete_all
  has_many :messages, dependent: :delete_all
  has_many :conversation_lorebooks, dependent: :destroy
  has_many :lorebooks, through: :conversation_lorebooks

  # Variables store for timed effects and other per-conversation state.
  # Used by TavernKit::Lore::TimedEffects for sticky/cooldown persistence.
  # Default value set in migration: {}

  # Get a ChatVariables-compatible store for this conversation.
  #
  # @return [Conversations::VariablesStore]
  def variables_store
    @variables_store ||= Conversations::VariablesStore.new(self)
  end

  # Normalizations
  normalizes :title, with: ->(value) { value&.strip.presence }

  # Enums (all string columns for readability)
  enum :kind, KINDS.index_by(&:itself), default: "root"
  enum :visibility, VISIBILITIES.index_by(&:itself), default: "shared", suffix: :conversation
  enum :status, STATUSES.index_by(&:itself), default: "ready"

  # Scopes
  # Find all conversations in the same tree (sharing the same root).
  # Includes both the root conversation itself AND all descendants.
  scope :in_tree, ->(root_id) { where(root_conversation_id: root_id).or(where(id: root_id)) }
  # Order by creation time (oldest first).
  scope :chronological, -> { order(created_at: :asc, id: :asc) }

  # Add last message content and timestamp to the result set.
  # Used for conversation list display.
  scope :with_last_message_preview, lambda {
    select(
      "#{table_name}.*",
      "(SELECT messages.content FROM messages " \
      "WHERE messages.conversation_id = #{table_name}.id " \
      "ORDER BY messages.created_at DESC, messages.id DESC LIMIT 1) AS last_message_content",
      "(SELECT messages.created_at FROM messages " \
      "WHERE messages.conversation_id = #{table_name}.id " \
      "ORDER BY messages.created_at DESC, messages.id DESC LIMIT 1) AS last_message_at"
    )
  }

  # Sort by most recent activity (last message time, falling back to updated_at).
  # Uses inline subquery to avoid dependency on SELECT alias.
  scope :by_recent_activity, lambda {
    order(Arel.sql(
            "COALESCE(" \
            "(SELECT messages.created_at FROM messages " \
            "WHERE messages.conversation_id = #{table_name}.id " \
            "ORDER BY messages.created_at DESC, messages.id DESC LIMIT 1), " \
            "#{table_name}.updated_at) DESC"
          ))
  }

  class << self
    # Access control for conversations based on visibility.
    #
    # - public: visible to everyone
    # - shared/private: visible only to space owner
    #
    # @param user [User, nil] the current user
    # @return [ActiveRecord::Relation]
    def accessible_to(user)
      public_records = arel_table[:visibility].eq("public")
      return where(public_records) unless user

      owned = Space.arel_table[:owner_id].eq(user.id)
      joins(:space).where(public_records.or(owned))
    end
  end

  # Override Publishable methods for Conversation's different visibility values.
  # Conversation uses shared/private/public instead of just private/public.

  # Check if the record is public (visible to everyone).
  def published?
    visibility == "public"
  end

  # Check if the record is not public.
  # For Conversation, both "shared" and "private" are not public.
  def draft?
    visibility != "public"
  end

  # Make the record public.
  def publish!
    update_column(:visibility, "public")
  end

  # Make the record private (back to shared for conversations).
  def unpublish!
    update_column(:visibility, "shared")
  end

  # Callbacks
  before_validation :assign_root_conversation, on: :create
  after_create :set_root_conversation_to_self, if: :root?

  # Custom counter cache callbacks (since Conversation belongs to Space, not directly to User)
  # Only count root conversations for User.conversations_count
  after_create :increment_owner_conversations_count, if: :root?
  after_destroy :decrement_owner_conversations_count, if: :root?

  # Validations
  validates :title, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :status, inclusion: { in: STATUSES }
  validates :scheduling_state, inclusion: { in: SCHEDULING_STATES }
  validates :auto_mode_remaining_rounds,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_AUTO_MODE_ROUNDS },
            allow_nil: true
  validate :kind_requires_parent
  validate :forked_from_message_belongs_to_parent

  # Query helpers
  def group?
    space.group?
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Scheduling state helpers
  # ─────────────────────────────────────────────────────────────────────────────

  # Check if scheduling is idle (no active round).
  def scheduling_idle?
    scheduling_state == "idle"
  end

  # Check if a round is actively being scheduled.
  def scheduling_active?
    scheduling_state != "idle" && scheduling_state != "failed"
  end

  # Check if AI is currently generating.
  def ai_generating?
    scheduling_state == "ai_generating"
  end

  # Check if waiting for human input.
  def human_waiting?
    scheduling_state == "human_waiting"
  end

  # Check if scheduling failed.
  def scheduling_failed?
    scheduling_state == "failed"
  end

  # Reset scheduling state to idle.
  def reset_scheduling!
    update!(
      scheduling_state: "idle",
      current_round_id: nil,
      current_speaker_id: nil,
      round_position: 0,
      round_spoken_ids: []
    )
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Auto-mode (AI-to-AI dialogue)
  # ─────────────────────────────────────────────────────────────────────────────

  # Check if auto-mode is currently active.
  # Auto-mode is only available for group chats.
  #
  # @return [Boolean] true if auto-mode has remaining rounds
  def auto_mode_enabled?
    auto_mode_remaining_rounds.to_i > 0
  end

  # Start auto-mode with a specified number of rounds.
  #
  # @param rounds [Integer] number of rounds (1-10, defaults to DEFAULT_AUTO_MODE_ROUNDS)
  def start_auto_mode!(rounds: DEFAULT_AUTO_MODE_ROUNDS)
    rounds = rounds.to_i.clamp(1, MAX_AUTO_MODE_ROUNDS)
    update!(auto_mode_remaining_rounds: rounds)
  end

  # Stop auto-mode immediately.
  def stop_auto_mode!
    update!(auto_mode_remaining_rounds: nil)
  end

  # Cancel all queued runs for this conversation.
  # Called when user submits a message to ensure their message takes priority.
  #
  # @param reason [String] the reason for cancellation (for debugging)
  # @return [Integer] number of runs canceled
  def cancel_all_queued_runs!(reason: "user_message")
    canceled_count = 0
    conversation_runs.queued.find_each do |run|
      run.canceled!(debug: (run.debug || {}).merge("canceled_by" => reason, "canceled_at" => Time.current.iso8601))
      canceled_count += 1
    end
    canceled_count
  end

  # Atomically decrement auto-mode remaining rounds.
  # Uses conditional UPDATE to avoid race conditions.
  #
  # If rounds reach 0, auto-mode is disabled (set to nil).
  # Broadcasts state changes to connected clients.
  #
  # @return [Boolean] true if successfully decremented, false if already at 0 or disabled
  def decrement_auto_mode_rounds!
    return false unless auto_mode_enabled?

    updated_count = Conversation
      .where(id: id)
      .where("auto_mode_remaining_rounds > 0")
      .update_all("auto_mode_remaining_rounds = auto_mode_remaining_rounds - 1")

    return false if updated_count == 0

    reload

    if auto_mode_remaining_rounds == 0
      # Exhausted - disable auto-mode
      Conversation.where(id: id, auto_mode_remaining_rounds: 0).update_all(auto_mode_remaining_rounds: nil)
      reload
      broadcast_auto_mode_exhausted
    else
      broadcast_auto_mode_round_used
    end

    true
  end

  # ─────────────────────────────────────────────────────────────────────────────

  # Check if conversation is ready for use (not pending fork).
  def forking_complete?
    ready?
  end

  # Mark forking as complete.
  def mark_forking_complete!
    update_column(:status, "ready")
  end

  # Mark forking as failed with error stored in variables.
  #
  # @param error [String] error message
  def mark_forking_failed!(error)
    transaction do
      update_columns(status: "failed", variables: (variables || {}).merge("_forking_error" => error))
    end
  end

  # Get forking error if any.
  #
  # @return [String, nil] error message
  def forking_error
    variables&.dig("_forking_error")
  end

  # Archive the conversation.
  def archive!
    update_column(:status, "archived")
  end

  # Unarchive the conversation (set back to ready).
  def unarchive!
    update_column(:status, "ready")
  end

  # Get all conversations in the same tree (including self).
  # Uses root_conversation_id for efficient querying.
  #
  # @return [ActiveRecord::Relation<Conversation>] all conversations in the tree
  def tree_conversations
    Conversation.in_tree(root_conversation_id || id)
  end

  def last_assistant_message
    messages.where(role: "assistant").order(:seq, :id).last
  end

  def last_user_message
    messages.where(role: "user").order(:seq, :id).last
  end

  def running_run
    conversation_runs.running.first
  end

  def queued_run
    conversation_runs.queued.first
  end

  def ai_respondable_participants
    space.ai_respondable_space_memberships
  end

  def create_first_messages!
    Conversations::FirstMessagesCreator.call(conversation: self)
  end

  # Create a branch (fork) from a specific message.
  #
  # This is a convenience method that wraps Conversations::Forker.
  # Creates a new conversation that copies messages up to and including
  # the specified message, then switches to the new branch.
  #
  # @param from_message [Message] the message to branch from (inclusive)
  # @param title [String, nil] title for the new branch (defaults to "Branch")
  # @param visibility [String] "shared" or "private" (defaults to "shared")
  # @param async [Boolean, nil] force async mode; if nil, auto-detects
  # @return [Conversations::Forker::Result] result with success?, conversation, error, async?
  #
  # @example Create a branch
  #   result = conversation.create_branch!(from_message: message, title: "My Branch")
  #   if result.success?
  #     redirect_to result.conversation
  #   end
  #
  def create_branch!(from_message:, title: nil, visibility: nil, async: nil)
    Conversations::Forker.new(
      parent_conversation: self,
      fork_from_message: from_message,
      kind: "branch",
      title: title,
      visibility: visibility,
      async: async
    ).call
  end

  # Create a thread from a specific message.
  #
  # Similar to create_branch! but creates a "thread" kind conversation.
  # Threads are allowed in all space types, while branches are limited
  # to Playground (solo) spaces.
  #
  # @param from_message [Message] the message to create thread from
  # @param title [String, nil] title for the thread
  # @param visibility [String] "shared" or "private"
  # @param async [Boolean, nil] force async mode; if nil, auto-detects
  # @return [Conversations::Forker::Result] result with success?, conversation, error, async?
  #
  def create_thread!(from_message:, title: nil, visibility: nil, async: nil)
    Conversations::Forker.new(
      parent_conversation: self,
      fork_from_message: from_message,
      kind: "thread",
      title: title,
      visibility: visibility,
      async: async
    ).call
  end

  # Create a checkpoint from the current state.
  #
  # A checkpoint is a snapshot of the conversation at a specific message.
  # Unlike branches, checkpoints are typically used for save points
  # rather than divergent timelines.
  #
  # @param from_message [Message] the message to checkpoint at
  # @param title [String, nil] title for the checkpoint
  # @param async [Boolean, nil] force async mode; if nil, auto-detects
  # @return [Conversations::Forker::Result] result with success?, conversation, error, async?
  #
  def create_checkpoint!(from_message:, title: nil, async: nil)
    Conversations::Forker.new(
      parent_conversation: self,
      fork_from_message: from_message,
      kind: "checkpoint",
      title: title,
      visibility: "shared",
      async: async
    ).call
  end

  private

  # ─────────────────────────────────────────────────────────────────────────────
  # Auto-mode broadcasts
  # ─────────────────────────────────────────────────────────────────────────────

  def broadcast_auto_mode_round_used
    ConversationChannel.broadcast_to(
      self,
      type: "auto_mode_round_used",
      conversation_id: id,
      remaining_rounds: auto_mode_remaining_rounds
    )
  end

  def broadcast_auto_mode_exhausted
    ConversationChannel.broadcast_to(
      self,
      type: "auto_mode_exhausted",
      conversation_id: id
    )
  end

  # ─────────────────────────────────────────────────────────────────────────────

  # For root conversations, root_conversation_id will be set to self after create.
  # For child conversations, inherit from parent.
  def assign_root_conversation
    return if root_conversation_id.present?

    if parent_conversation.present?
      self.root_conversation_id = parent_conversation.root_conversation_id
    end
    # For root conversations, we set it after create since we need the id
  end

  # After creating a root conversation, set root_conversation_id to self.
  def set_root_conversation_to_self
    update_column(:root_conversation_id, id) if root_conversation_id.nil?
  end

  def kind_requires_parent
    case kind
    when "root"
      errors.add(:parent_conversation, "must be blank for root conversations") if parent_conversation_id.present?
    when "branch", "thread", "checkpoint"
      errors.add(:parent_conversation, "must be present for #{kind} conversations") if parent_conversation_id.blank?
    end

    if parent_conversation && parent_conversation.space_id != space_id
      errors.add(:parent_conversation, "must belong to the same space")
    end
  end

  def forked_from_message_belongs_to_parent
    return if forked_from_message_id.blank?

    if parent_conversation_id.blank?
      errors.add(:forked_from_message, "cannot be set without a parent conversation")
      return
    end

    unless forked_from_message&.conversation_id == parent_conversation_id
      errors.add(:forked_from_message, "must belong to the parent conversation")
    end
  end

  # Delete message attachments before deleting messages.
  # Called before destroy since we use `dependent: :delete_all` which skips callbacks.
  def delete_message_attachments
    MessageAttachment
      .joins(:message)
      .where(messages: { conversation_id: id })
      .delete_all
  end

  # Decrement TextContent references for all messages and swipes before delete.
  # Called before destroy since we use `dependent: :delete_all` which skips callbacks.
  def decrement_text_content_references
    # Collect text_content_ids from messages
    message_text_content_ids = messages.where.not(text_content_id: nil).pluck(:text_content_id)

    # Collect text_content_ids from swipes
    swipe_text_content_ids = MessageSwipe
      .joins(:message)
      .where(messages: { conversation_id: id })
      .where.not(message_swipes: { text_content_id: nil })
      .pluck(:text_content_id)

    # Batch decrement all text content references
    all_ids = (message_text_content_ids + swipe_text_content_ids)

    # Count occurrences and decrement by the right amount
    id_counts = all_ids.tally
    id_counts.each do |tc_id, count|
      TextContent.where(id: tc_id).update_all(["references_count = references_count - ?", count])
    end
  end

  # Increment conversations_count on the Space owner (User).
  # Only called for root conversations.
  def increment_owner_conversations_count
    return unless space&.owner_id

    User.where(id: space.owner_id).update_all("conversations_count = conversations_count + 1")
  end

  # Decrement conversations_count on the Space owner (User).
  # Only called for root conversations.
  def decrement_owner_conversations_count
    return unless space&.owner_id

    User.where(id: space.owner_id).where("conversations_count > 0").update_all("conversations_count = conversations_count - 1")
  end
end
