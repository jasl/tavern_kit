# frozen_string_literal: true

# User model for authentication and authorization.
#
# Roles:
# - member: Regular user (default)
# - moderator: Can manage conversations and messages
# - administrator: Full access to manage characters, presets, lorebooks, etc.
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
class User < ApplicationRecord
  ROLES = %w[member moderator administrator].freeze
  STATUSES = %w[active inactive].freeze

  has_many :sessions, dependent: :destroy
  has_many :character_uploads, dependent: :destroy

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
  validates :email, uniqueness: { case_sensitive: false }, allow_nil: true

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order("LOWER(name)") }

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

  private

  # Password is required when creating a new user or updating password
  def password_required?
    new_record? || password.present?
  end
end
