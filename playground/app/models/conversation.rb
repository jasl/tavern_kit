# frozen_string_literal: true

# Conversation model for a message timeline inside a Space.
#
# Tree structure fields:
# - parent_conversation_id: direct parent (nullable for root)
# - root_conversation_id: the root of the tree (self for root conversations)
# - forked_from_message_id: the message in parent where this conversation branched from
#
class Conversation < ApplicationRecord
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

  def root?
    kind == "root"
  end

  def checkpoint?
    kind == "checkpoint"
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
    created = []

    space.character_space_memberships.by_position.includes(:character).each do |membership|
      first_mes = membership.character&.first_mes
      next if first_mes.blank?

      created << messages.create!(
        space_membership: membership,
        role: "assistant",
        content: first_mes
      )
    end

    created
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
