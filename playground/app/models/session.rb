# frozen_string_literal: true

# Session model for user authentication.
#
# Sessions track user login state with secure tokens stored in cookies.
# Activity is tracked and refreshed periodically.
#
# @example Start a new session
#   user.sessions.start!(user_agent: "Mozilla/5.0...", ip_address: "127.0.0.1")
#
class Session < ApplicationRecord
  ACTIVITY_REFRESH_RATE = 1.hour

  has_secure_token

  belongs_to :user

  before_create { self.last_active_at ||= Time.current }

  # Start a new session for a user.
  #
  # @param user_agent [String] browser user agent
  # @param ip_address [String] client IP address
  # @return [Session] the created session
  def self.start!(user_agent:, ip_address:)
    create!(user_agent: user_agent, ip_address: ip_address)
  end

  # Resume an existing session, updating activity timestamp if stale.
  #
  # @param user_agent [String] browser user agent
  # @param ip_address [String] client IP address
  def resume(user_agent:, ip_address:)
    if last_active_at.before?(ACTIVITY_REFRESH_RATE.ago)
      update!(user_agent: user_agent, ip_address: ip_address, last_active_at: Time.current)
    end
  end
end
