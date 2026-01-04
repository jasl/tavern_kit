# frozen_string_literal: true

# CurrentAttributes for request-scoped state.
#
# Provides access to the current user and request throughout
# the request lifecycle.
#
# @example Access current user
#   Current.user
#   # => #<User id: 1, name: "Admin", ...>
#
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :request

  delegate :host, :protocol, to: :request, prefix: true, allow_nil: true
end
