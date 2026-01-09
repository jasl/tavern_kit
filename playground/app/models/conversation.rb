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
  # @return [ConversationVariablesStore]
  def variables_store
    @variables_store ||= ConversationVariablesStore.new(self)
  end

  # ChatVariables-compatible store backed by conversation.variables jsonb.
  # Must implement get/set (not just []/[]=) because macro engine calls get/set directly.
  class ConversationVariablesStore < TavernKit::ChatVariables::Base
    def initialize(conversation)
      @conversation = conversation
    end

    def get(key)
      variables_hash[key.to_s]
    end
    alias [] get

    def set(key, value)
      key = key.to_s
      variables_hash[key] = value

      persist_set!(key, value) if @conversation.persisted?
      value
    end
    alias []= set

    def delete(key)
      key = key.to_s
      result = variables_hash.delete(key)

      persist_delete!(key) if @conversation.persisted?
      result
    end

    def key?(key)
      variables_hash.key?(key.to_s)
    end

    def each(&block)
      return to_enum(:each) unless block_given?

      variables_hash.each(&block)
    end

    def size
      variables_hash.size
    end

    def clear
      variables_hash.clear
      persist_clear! if @conversation.persisted?
      self
    end

    private

    def variables_hash
      @conversation.variables ||= {}
    end

    # Persist a single key update atomically (jsonb_set) to avoid lost updates
    # when multiple processes update different keys concurrently.
    def persist_set!(key, value)
      now = Time.current

      Conversation.where(id: @conversation.id).update_all([
        "variables = jsonb_set(COALESCE(variables, '{}'::jsonb), ARRAY[?]::text[], ?::jsonb, true), updated_at = ?",
        key,
        value.to_json,
        now,
      ])

      @conversation.updated_at = now
    end

    # Persist a single key delete atomically (jsonb - key).
    def persist_delete!(key)
      now = Time.current

      Conversation.where(id: @conversation.id).update_all([
        "variables = COALESCE(variables, '{}'::jsonb) - ?, updated_at = ?",
        key,
        now,
      ])

      @conversation.updated_at = now
    end

    def persist_clear!
      now = Time.current

      Conversation.where(id: @conversation.id).update_all(variables: {}, updated_at: now)
      @conversation.updated_at = now
    end
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
  validate :kind_requires_parent
  validate :forked_from_message_belongs_to_parent

  # Query helpers
  def group?
    space.group?
  end

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
