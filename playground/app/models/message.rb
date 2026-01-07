# frozen_string_literal: true

# Message model for chat messages in conversations.
#
# Messages are sent by SpaceMemberships (not directly by Users or Characters),
# which allows both human users and AI characters to send messages within a Space.
#
# Content is stored as plain text in the `content` column (nullable for placeholders).
#
# Concurrency Strategy:
# Uses optimistic retry for seq assignment. The unique index on (conversation_id, seq)
# prevents duplicate sequences. If a conflict occurs during creation, the message
# retries with a new sequence number.
#
# @example Create a user message
#   conversation.messages.create!(space_membership: user_membership, content: "Hello!")
#
# @example Create an AI placeholder
#   conversation.messages.create!(space_membership: character_membership, role: :assistant, content: nil)
#
class Message < ApplicationRecord
  include Broadcasts

  # Message roles (OpenAI chat format)
  # - user: Human user message
  # - assistant: AI response
  # - system: System/instruction message
  ROLES = %w[user assistant system].freeze

  # Associations
  belongs_to :conversation, touch: true
  belongs_to :space_membership
  belongs_to :conversation_run, optional: true

  # Clone mapping: tracks which message this was copied from during fork
  belongs_to :origin_message, class_name: "Message", optional: true
  has_many :cloned_messages, class_name: "Message",
                             foreign_key: :origin_message_id,
                             dependent: :nullify,
                             inverse_of: :origin_message

  # Conversation fork mapping: conversations that branched from this message.
  # Uses restrict_with_error to prevent deletion of fork point messages,
  # ensuring referential integrity for the conversation tree.
  has_many :forked_conversations, class_name: "Conversation",
                                  foreign_key: :forked_from_message_id,
                                  dependent: :restrict_with_error,
                                  inverse_of: :forked_from_message

  # Swipe associations - multiple versions of AI responses
  has_many :message_swipes, -> { order(:position) }, dependent: :destroy, inverse_of: :message
  belongs_to :active_message_swipe, class_name: "MessageSwipe", optional: true

  # Normalizations - strip whitespace from content
  normalizes :content, with: ->(value) { value&.strip }

  # Enum for role
  enum :role, ROLES.index_by(&:itself), default: "user"

  # Validations
  validates :seq, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :seq, uniqueness: { scope: :conversation_id }, if: -> { seq.present? }
  validates :role, inclusion: { in: ROLES }
  # Content is required for user messages, but can be blank:
  # - for assistant messages (they start empty and are filled via streaming)
  # - for generating messages (placeholder created before LLM response)
  validates :content, presence: true, unless: -> { assistant? || generating? }

  # Callbacks
  before_create :assign_seq

  # Override create to handle seq conflicts with retry
  def self.create(attributes = nil, &block)
    create_with_seq_retry(attributes, raise_on_failure: false, &block)
  end

  def self.create!(attributes = nil, &block)
    create_with_seq_retry(attributes, raise_on_failure: true, &block)
  end

  # Creates a message with automatic retry on seq conflict.
  # The unique index on (conversation_id, seq) may cause conflicts
  # when concurrent messages are created in the same conversation.
  MAX_SEQ_RETRIES = 10

  def self.create_with_seq_retry(attributes, raise_on_failure:, &block)
    retries = 0
    begin
      # Create a fresh record each attempt since before_create callbacks
      # only run once per save attempt
      record = new(attributes, &block)
      raise_on_failure ? record.save! : record.save
      record
    rescue ActiveRecord::RecordNotUnique => e
      # Only retry for seq conflicts, not other uniqueness violations.
      raise unless seq_conflict?(e)

      retries += 1
      raise if retries >= MAX_SEQ_RETRIES

      retry
    end
  end
  private_class_method :create_with_seq_retry

  def self.seq_conflict?(error)
    constraint =
      if defined?(PG) && error.cause.respond_to?(:result)
        error.cause.result&.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)
      end

    return true if constraint == "index_messages_on_conversation_id_and_seq"

    message = error.message.to_s
    message.include?("index_messages_on_conversation_id_and_seq") ||
      (message.include?("conversation_id") && message.include?("seq"))
  end
  private_class_method :seq_conflict?

  # Sync content changes to active swipe to maintain consistency.
  # When message.content is edited directly (e.g., via MessagesController#update),
  # the active swipe must be updated to match.
  after_update :sync_content_to_active_swipe, if: :should_sync_content_to_swipe?

  # Scopes
  # Chronological ordering (oldest first).
  # Uses id as a tiebreaker for stable pagination when created_at is equal.
  scope :ordered, -> { order(:seq, :id) }
  scope :with_space_membership, -> {
    includes(space_membership: %i[user character])
      .includes(:active_message_swipe)
  }
  scope :with_participant, -> { with_space_membership }

  # Messages that should be included in prompt building.
  # Excludes messages marked as excluded_from_prompt.
  scope :included_in_prompt, -> { where(excluded_from_prompt: false) }

  # Get most recent messages (newest first).
  # Note: Uses reorder() to override any prior ordering.
  scope :recent, ->(limit = 50) { reorder(created_at: :desc, id: :desc).limit(limit) }

  # Get the most recent messages, returned in chronological order (oldest -> newest).
  #
  # This avoids the common but inefficient pattern of `recent(limit).reverse`, which
  # forces Rails to load records and reverse them in memory.
  #
  # Implementation:
  # - Inner query selects the newest N ids efficiently (ORDER BY created_at DESC, id DESC LIMIT N)
  # - Outer query returns those rows ordered chronologically for display
  scope :recent_chronological, lambda { |limit = 50|
    ids = reorder(created_at: :desc, id: :desc).limit(limit).select(:id)
    where(id: ids).reorder(created_at: :asc, id: :asc)
  }

  # Cursor helpers for pagination.
  #
  # These use (created_at, id) as a stable cursor.
  scope :before_cursor, lambda { |cursor|
    where(
      "messages.created_at < :created_at OR (messages.created_at = :created_at AND messages.id < :id)",
      created_at: cursor.created_at,
      id: cursor.id
    )
  }

  scope :after_cursor, lambda { |cursor|
    where(
      "messages.created_at > :created_at OR (messages.created_at = :created_at AND messages.id > :id)",
      created_at: cursor.created_at,
      id: cursor.id
    )
  }

  # Cursor pagination helpers.
  #
  # - page_before_cursor: previous page (closest older messages), returned chronological
  # - page_after_cursor: next page (newest newer messages), returned chronological
  scope :page_before_cursor, lambda { |cursor, limit = 50|
    before_cursor(cursor).recent_chronological(limit)
  }

  scope :page_after_cursor, lambda { |cursor, limit = 50|
    after_cursor(cursor).recent_chronological(limit)
  }

  # Delegate display_name to membership for convenience
  delegate :display_name, to: :space_membership, prefix: :sender

  # --- generation helpers (Run-driven) ---

  def generating?
    conversation_run&.running? == true
  end

  def generated?
    conversation_run&.succeeded? == true
  end

  def errored?
    conversation_run&.failed? == true || metadata&.dig("error").present?
  end

  def ai_generated?
    conversation_run_id.present?
  end

  # Get the error message if generation failed.
  #
  # @return [String, nil]
  def error_message
    metadata&.dig("error")
  end

  # --- Content helpers ---

  # Plain text content for backward compatibility.
  #
  # @return [String]
  def plain_text_content
    content.presence || ""
  end

  # Alias for text to ease migration (some code may still use .text).
  #
  # @return [String, nil]
  def text
    content
  end

  # Check if this is a user message.
  #
  # @return [Boolean]
  def user_message?
    role == "user"
  end

  # Check if this is an AI assistant message.
  #
  # @return [Boolean]
  def assistant_message?
    role == "assistant"
  end

  # Check if this is a system message.
  #
  # @return [Boolean]
  def system_message?
    role == "system"
  end

  # Check if the sender is a character (AI).
  #
  # @return [Boolean]
  def from_character?
    space_membership.ai_character?
  end

  # Check if the sender is a user (human).
  #
  # @return [Boolean]
  def from_user?
    space_membership.user?
  end

  # --- Swipe methods ---

  # Check if this message can be swiped (has multiple versions).
  #
  # @return [Boolean]
  def swipeable?
    message_swipes_count > 1
  end

  # Get the position of the active swipe (1-based for display).
  #
  # @return [Integer] position (1-based), or 1 if no swipes
  def active_swipe_position
    active_message_swipe&.position.to_i + 1
  end

  # Ensure the message has an initial swipe.
  # Creates a position=0 swipe from current content if none exist.
  # Uses optimistic concurrency with the unique index on (message_id, position).
  #
  # @return [MessageSwipe] the initial or existing first swipe
  def ensure_initial_swipe!
    Messages::Swipes::InitialSwipeEnsurer.call(message: self)
  end

  # Add a new swipe version to this message.
  # Creates a new swipe at the next position and sets it as active.
  # Also syncs message.content to match the new swipe.
  # Uses optimistic retry with the unique index on (message_id, position).
  #
  # @param content [String] the swipe content
  # @param metadata [Hash] optional metadata
  # @param conversation_run_id [String, nil] the ConversationRun that generated this swipe
  # @return [MessageSwipe] the created swipe
  def add_swipe!(content:, metadata: {}, conversation_run_id: nil)
    Messages::Swipes::Adder.call(
      message: self,
      content: content,
      metadata: metadata,
      conversation_run_id: conversation_run_id
    )
  end

  # Select a swipe by navigating left or right.
  # Updates active_message_swipe and syncs message.content.
  # No locking needed - just a simple read and update.
  #
  # @param direction [Symbol] :left or :right
  # @return [MessageSwipe, nil] the newly selected swipe, or nil if at boundary
  def select_swipe!(direction:)
    Messages::Swipes::Selector.select_by_direction!(message: self, direction: direction)
  end

  # Select a swipe by position (0-based).
  # No locking needed - just a simple read and update.
  #
  # @param position [Integer] the swipe position to select
  # @return [MessageSwipe, nil] the selected swipe, or nil if not found
  def select_swipe_at!(position)
    Messages::Swipes::Selector.select_at!(message: self, position: position)
  end

  # Check if the active swipe is the first (leftmost).
  #
  # @return [Boolean]
  def at_first_swipe?
    active_message_swipe&.position.to_i.zero?
  end

  # Check if the active swipe is the last (rightmost).
  # Uses message_swipes_count to avoid SQL query (positions are sequential 0..n-1).
  #
  # @return [Boolean]
  def at_last_swipe?
    return true unless active_message_swipe

    active_message_swipe.position >= last_swipe_position
  end

  # Get the last swipe position (0-based).
  # Returns 0 when no swipes exist.
  #
  # @return [Integer]
  def last_swipe_position
    [message_swipes_count.to_i - 1, 0].max
  end

  # --- Fork point methods ---

  # Check if this message is a fork point (referenced by child conversations).
  # Fork point messages cannot be deleted or modified to preserve timeline integrity.
  #
  # @return [Boolean] true if any conversation branches from this message
  def fork_point?
    forked_conversations.exists?
  end

  # --- Context visibility methods ---

  # Toggle the message's inclusion in prompt context.
  # Excluded messages remain visible in UI but are not sent to the LLM.
  #
  # @return [Boolean] the new excluded_from_prompt value
  def toggle_prompt_visibility!
    update!(excluded_from_prompt: !excluded_from_prompt)
    excluded_from_prompt
  end

  private

  # Assigns a unique sequence number.
  # Called before create. If a conflict occurs (another message was created
  # concurrently), the create_with_seq_retry class method will handle retry.
  def assign_seq
    return if seq.present?
    return if conversation_id.blank?

    self.seq = (conversation.messages.maximum(:seq) || 0) + 1
  end

  # Check if content should be synced to active swipe.
  # Only sync when:
  # - content actually changed
  # - there is an active swipe
  # - swipe content differs from message content
  #
  # @return [Boolean]
  def should_sync_content_to_swipe?
    saved_change_to_content? &&
      active_message_swipe.present? &&
      active_message_swipe.content != content
  end

  # Sync message content to the active swipe.
  # This ensures consistency when content is edited directly.
  #
  # @return [void]
  def sync_content_to_active_swipe
    active_message_swipe.update!(content: content)
  end
end
