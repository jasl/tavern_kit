# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include GearedPagination::Controller
  include SetCurrentRequest
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  rescue_from LLMClient::NoProviderError, with: :handle_llm_provider_missing

  private

  def toast_turbo_stream(message:, type: "info", duration: 5000)
    turbo_stream.action(
      :show_toast,
      nil,
      partial: "shared/toast",
      locals: { message: message, type: type, duration: duration }
    )
  end

  def render_toast_turbo_stream(message:, type: "info", duration: 5000, status: :unprocessable_entity)
    response.set_header("X-TavernKit-Toast", "1")
    render turbo_stream: toast_turbo_stream(message: message, type: type, duration: duration), status: status
  end

  def handle_llm_provider_missing
    message = t(
      "llm_providers.errors.no_default_provider",
      default: "No LLM provider configured. Please set a default provider in Settings."
    )

    respond_to do |format|
      format.turbo_stream do
        render_toast_turbo_stream(message: message, type: "warning", duration: 5000, status: :unprocessable_entity)
      end
      format.html { redirect_back fallback_location: root_url, alert: message }
      format.json { render json: { error: message }, status: :unprocessable_entity }
      format.any { head :unprocessable_entity }
    end
  end
end
