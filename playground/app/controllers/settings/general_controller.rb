# frozen_string_literal: true

module Settings
  # General system-wide settings controller.
  #
  # Manages global configuration options that affect all users/spaces,
  # such as token limits and other administrative settings.
  class GeneralController < Settings::ApplicationController
    # GET /settings/general
    def index
      @max_token_limit = Setting.get("space.max_token_limit")&.to_i
    end

    # PATCH /settings/general
    def update
      max_token_limit = general_params[:max_token_limit]

      # Coerce to integer, nil if blank or zero
      max_token_limit_value = if max_token_limit.present?
                                value = max_token_limit.to_i
                                value.positive? ? value.to_s : nil
      end

      if max_token_limit_value
        Setting.set("space.max_token_limit", max_token_limit_value)
      else
        Setting.delete("space.max_token_limit")
      end

      redirect_to settings_general_path,
                  notice: t("settings.general.updated", default: "General settings updated successfully.")
    end

    private

    def general_params
      params.permit(:max_token_limit)
    end
  end
end
