# frozen_string_literal: true

# Invite codes for user registration.
#
# Admins can create invite codes that users can use to register.
# Codes can have optional expiration dates and usage limits.
#
# @example Create a code with no limits
#   InviteCode.generate!(created_by: admin, note: "General invite")
#
# @example Create a code with limits
#   InviteCode.generate!(created_by: admin, max_uses: 10, expires_at: 1.week.from_now)
#
# @example Check if code is valid
#   code.valid_for_use? # => true/false
#
class InviteCode < ApplicationRecord
  CODE_FORMAT = /\A[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\z/

  belongs_to :created_by, class_name: "User", optional: true
  has_many :users, foreign_key: :invited_by_code_id, dependent: :nullify, inverse_of: :invited_by_code

  validates :code, presence: true, uniqueness: true, format: { with: CODE_FORMAT }
  validates :max_uses, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  before_validation :generate_code, on: :create, if: -> { code.blank? }

  scope :active, -> { where("(expires_at IS NULL OR expires_at > ?) AND (max_uses IS NULL OR uses_count < max_uses)", Time.current) }
  scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
  scope :exhausted, -> { where("max_uses IS NOT NULL AND uses_count >= max_uses") }
  scope :ordered, -> { order(created_at: :desc) }

  # Generate a new invite code.
  #
  # @param created_by [User] the admin creating the code
  # @param note [String, nil] optional note about the code
  # @param max_uses [Integer, nil] maximum number of uses (nil = unlimited)
  # @param expires_at [DateTime, nil] expiration time (nil = never)
  # @return [InviteCode] the created invite code
  def self.generate!(created_by:, note: nil, max_uses: nil, expires_at: nil)
    create!(
      created_by: created_by,
      note: note,
      max_uses: max_uses,
      expires_at: expires_at
    )
  end

  # Check if this code can still be used for registration.
  #
  # @return [Boolean] true if the code is valid for use
  def valid_for_use?
    !expired? && !exhausted?
  end

  # Check if the code has expired.
  #
  # @return [Boolean] true if expired
  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  # Check if the code has reached its usage limit.
  #
  # @return [Boolean] true if exhausted
  def exhausted?
    max_uses.present? && uses_count >= max_uses
  end

  # Increment the usage count (called when a user registers with this code).
  # Note: This is typically handled via counter_cache on User model.
  def increment_uses!
    increment!(:uses_count)
  end

  private

  # Generate a random code in XXXX-XXXX-XXXX format.
  def generate_code
    self.code = self.class.generate_unique_code
  end

  # Generate a unique code that doesn't exist in the database.
  #
  # @return [String] unique code
  def self.generate_unique_code
    loop do
      code = SecureRandom.alphanumeric(12).upcase.scan(/.{4}/).join("-")
      break code unless exists?(code: code)
    end
  end
end
