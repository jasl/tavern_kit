# frozen_string_literal: true

# Tracks the last space visited by the user.
#
# Stores the last visited space ID in a permanent cookie for
# persistence across sessions.
#
# @example Include in RoomsController
#   class RoomsController < ApplicationController
#     include TrackedRoomVisit
#     before_action :remember_last_room_visited, only: :show
#   end
#
module TrackedSpaceVisit
  extend ActiveSupport::Concern

  included do
    helper_method :last_space_visited
  end

  # Save the current space as the last visited space.
  #
  # @return [void]
  def remember_last_space_visited
    cookies.permanent[:last_space] = @space.id
  end

  # Get the last space visited by the current user.
  #
  # @return [Space, nil] the last visited space or a default space
  def last_space_visited
    Current.user.spaces.merge(Space.accessible_to(Current.user)).find_by(id: cookies[:last_space]) || default_space
  end

  private

  # Get the default space when no last space is available.
  #
  # @return [Space, nil] the first created space the user has access to
  def default_space
    Current.user.spaces.merge(Space.accessible_to(Current.user)).order(:created_at).first
  end
end
