# frozen_string_literal: true

module ApplicationCable
  # Base class for all ActionCable channels.
  #
  # Provides access to the current user via the connection.
  #
  class Channel < ActionCable::Channel::Base
  end
end
