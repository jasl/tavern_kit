# frozen_string_literal: true

# Sets the current request on Current for access throughout the request.
#
# This concern makes the request object available via Current.request
# and provides default URL options based on the current request.
#
module SetCurrentRequest
  extend ActiveSupport::Concern

  included do
    before_action do
      Current.request = request
    end
  end

  def default_url_options
    { host: Current.request_host, protocol: Current.request_protocol }.compact_blank
  end
end
