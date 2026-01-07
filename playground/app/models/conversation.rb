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
  VISIBILITIES = %w[shared private].freeze

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

  # Enums
  enum :kind, KINDS.index_by(&:itself), default: "root"
  enum :visibility, VISIBILITIES.index_by(&:itself), default: "shared", suffix: :conversation

  # Scopes
  # Find all conversations in the same tree (sharing the same root).
  scope :in_tree, ->(root_id) { where(root_conversation_id: root_id) }
  # Order by creation time (oldest first).
  scope :chronological, -> { order(created_at: :asc, id: :asc) }

  class << self
    def accessible_to(user, now: Time.current)
      published = arel_table[:published_at].lt(now)
      return where(published) unless user

      owner_draft = arel_table[:published_at].eq(nil).and(Space.arel_table[:owner_id].eq(user.id))
      joins(:space).where(published.or(owner_draft))
    end
  end

  # Callbacks
  before_validation :assign_root_conversation, on: :create
  after_create :set_root_conversation_to_self, if: :root?

  # Validations
  validates :title, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validate :kind_requires_parent
  validate :forked_from_message_belongs_to_parent

  # Query helpers
  def group?
    space.group?
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
    conversation_runs.where(status: "running").order(:created_at, :id).last
  end

  def queued_run
    conversation_runs.where(status: "queued").order(:created_at, :id).last
  end

  def ai_respondable_participants
    space.ai_respondable_space_memberships
  end

  def create_first_messages!
    Conversations::FirstMessagesCreator.call(conversation: self)
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
end
