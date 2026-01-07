# frozen_string_literal: true

# Base controller for all playground-scoped controllers.
#
# Sets up @playground and @space_membership context, ensuring the current user
# has access to the playground via their membership.
#
# @example Create a nested controller
#   class Playgrounds::CopilotCandidatesController < Playgrounds::ApplicationController
#     # @playground and @space_membership are already available
#   end
#
module Playgrounds
  class ApplicationController < ::ApplicationController
    before_action :set_playground

    private

    # Set the current playground from the playground_id parameter.
    #
    # @raise [ActiveRecord::RecordNotFound] if the user is not a member of the playground
    def set_playground
      @playground = Spaces::Playground.accessible_to(Current.user).find(params[:playground_id])
      # Also set @space for Authorization concern compatibility
      @space = @playground

      # Verify user has access via space membership
      @space_membership = Current.user.space_memberships.active.find_by!(space_id: @playground.id)
    end
  end
end
