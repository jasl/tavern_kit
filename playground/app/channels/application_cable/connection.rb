# frozen_string_literal: true

module ApplicationCable
  # WebSocket connection handler with session-based authentication.
  #
  # Uses the same session cookie as the HTTP layer to authenticate
  # WebSocket connections.
  #
  # @example Automatic authentication
  #   # When a client connects to /cable, this class verifies
  #   # their session cookie and identifies them as current_user
  #
  class Connection < ActionCable::Connection::Base
    include Authentication::SessionLookup

    identified_by :current_user

    # Called when a WebSocket connection is established.
    # Verifies the user's session and sets the current_user.
    def connect
      self.current_user = find_verified_user
    end

    private

    # Find and verify the user from their session cookie.
    #
    # @return [User] the verified user
    # @raise [ActionCable::Connection::Authorization::UnauthorizedError] if no valid session
    def find_verified_user
      if (verified_session = find_session_by_cookie)
        verified_session.user
      else
        reject_unauthorized_connection
      end
    end
  end
end
