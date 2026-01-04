# frozen_string_literal: true

module Schemas
  class SettingsController < ApplicationController
    # GET /schemas/settings
    def show
      return unless stale?(etag: SettingsSchemaPack.digest, public: true)

      expires_in 5.minutes, public: true
      render json: SettingsSchemaPack.bundle
    end
  end
end
