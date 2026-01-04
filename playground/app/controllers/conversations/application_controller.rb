# frozen_string_literal: true

# Base controller for all conversation-scoped controllers.
#
# Sets up @conversation and @space context, ensuring the current user
# has access to the conversation via their space membership.
#
# @example Create a nested controller
#   class Conversations::MessagesController < Conversations::ApplicationController
#     # @conversation and @space are already available
#   end
#
module Conversations
  class ApplicationController < ::ApplicationController
    before_action :set_conversation

    private

    # Set the current conversation and space from the conversation_id parameter.
    #
    # @raise [ActiveRecord::RecordNotFound] if the user is not a member of the space
    def set_conversation
      @conversation = Conversation.find(params[:conversation_id] || params[:id])
      @space = @conversation.space

      # Verify user has access via space membership
      @space_membership = Current.user.space_memberships.active.find_by!(space_id: @space.id)
    end
  end
end
