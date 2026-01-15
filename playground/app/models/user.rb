# frozen_string_literal: true

# User model for authentication and authorization.
#
# Roles:
# - member: Regular user (default)
# - moderator: Can manage conversations and messages
# - administrator: Full access to manage characters, presets, lorebooks, etc.
#
# Statuses:
# - active: Normal active user (default)
# - inactive: Deactivated user (cannot log in, sessions cleared)
#
# Note: User's identity in chat spaces is per-space via SpaceMembership model.
# Users can use different personas in different spaces.
#
# @example Create an administrator
#   User.create!(name: "Admin", email: "admin@example.com",
#                password: "secret", role: :administrator)
#
# @example Find active users
#   User.active.ordered
#
# @example Deactivate a user
#   user.deactivate! # Clears all sessions
#
class User < ApplicationRecord
  ROLES = %w[member moderator administrator].freeze
  STATUSES = %w[active inactive].freeze

  # Invitation tracking
  belongs_to :invited_by_code, class_name: "InviteCode", optional: true, counter_cache: :uses_count

  has_many :sessions, dependent: :destroy
  has_many :character_uploads, dependent: :destroy

  # Content ownership (for counter caches)
  has_many :characters, dependent: :nullify
  has_many :lorebooks, dependent: :nullify

  # Space/chat associations
  # Note: Using nullify to preserve chat history when user is deleted
  has_many :space_memberships, dependent: :nullify
  has_many :active_space_memberships, -> { active }, class_name: "SpaceMembership"
  has_many :spaces, through: :active_space_memberships
  has_many :owned_spaces, class_name: "Space", foreign_key: :owner_id, dependent: :nullify, inverse_of: :owner

  has_secure_password validations: false

  # 使用 string 存储枚举值以保持可读性
  enum :role, ROLES.index_by(&:itself), default: "member"
  enum :status, STATUSES.index_by(&:itself), default: "active"

  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :password, presence: true, length: { minimum: 6 }, if: :password_required?
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where(status: "inactive") }
  scope :ordered, -> { order("LOWER(name)") }
  scope :by_created_at, -> { order(created_at: :desc) }

  # Authenticate a user by email and password.
  #
  # @param email [String] user's email
  # @param password [String] user's password
  # @return [User, nil] authenticated user or nil
  def self.authenticate_by(email:, password:)
    find_by(email: email)&.authenticate(password) || nil
  end

  # Check if user can administer resources (characters, presets, etc.).
  #
  # @return [Boolean] true if administrator
  def can_administer?
    administrator?
  end

  # Check if user can moderate (manage conversations, messages).
  #
  # @return [Boolean] true if moderator or administrator
  def can_moderate?
    administrator? || moderator?
  end

  # Deactivate the user and clear all sessions.
  # Deactivated users cannot log in until reactivated.
  #
  # @return [void]
  def deactivate!
    transaction do
      sessions.destroy_all
      update!(status: "inactive")
    end
  end

  # Reactivate a deactivated user.
  #
  # @return [void]
  def activate!
    update!(status: "active")
  end

  private

  # Password is required when creating a new user or updating password
  def password_required?
    new_record? || password.present?
  end
end
