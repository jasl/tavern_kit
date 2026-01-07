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

    rescue_from ActiveRecord::RecordNotFound, with: :playground_not_found

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

    def playground_not_found
      message = t("playgrounds.not_found", default: "Playground not found")

      respond_to do |format|
        format.html { redirect_to root_url, alert: message }
        format.turbo_stream { redirect_to root_url, alert: message }
        format.json { render json: { error: message }, status: :not_found }
        format.any { head :not_found }
      end
    end
  end
end
