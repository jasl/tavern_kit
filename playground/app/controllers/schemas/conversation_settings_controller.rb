# frozen_string_literal: true

module Schemas
  class ConversationSettingsController < ApplicationController
    # GET /schemas/conversation_settings
    def show
      return unless stale?(etag: ConversationSettings::SchemaBundle.etag, public: true)

      expires_in 5.minutes, public: true
      render json: ConversationSettings::SchemaBundle.schema
    end
  end
end
