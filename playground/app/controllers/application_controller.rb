# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include GearedPagination::Controller
  include SetCurrentRequest
  include Authentication

  protect_from_forgery with: :exception

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  rescue_from LLMClient::NoProviderError, with: :handle_llm_provider_missing

  private

  def handle_llm_provider_missing
    message = t(
      "llm_providers.errors.no_default_provider",
      default: "No LLM provider configured. Please set a default provider in Settings."
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: render_to_string(
          partial: "shared/toast_turbo_stream",
          locals: { message: message, type: "warning", duration: 5000 }
        ), status: :unprocessable_entity
      end
      format.html { redirect_back fallback_location: root_url, alert: message }
      format.json { render json: { error: message }, status: :unprocessable_entity }
      format.any { head :unprocessable_entity }
    end
  end
end
