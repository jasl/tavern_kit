# frozen_string_literal: true

# Shared session lookup for both controllers and ActionCable connections.
#
# This module provides the common `find_session_by_cookie` method that can be
# used in both HTTP request contexts (controllers) and WebSocket contexts
# (ActionCable connections).
#
# @example Include in ActionCable connection
#   class Connection < ActionCable::Connection::Base
#     include Authentication::SessionLookup
#
#     def connect
#       self.current_user = find_session_by_cookie&.user || reject_unauthorized_connection
#     end
#   end
#
module Authentication
  module SessionLookup
    # Find session by token stored in cookie.
    #
    # @return [Session, nil] the session or nil
    def find_session_by_cookie
      return unless (token = cookies.signed[:session_token])

      Session.find_by(token: token)
    end
  end
end
