# frozen_string_literal: true

class SessionsController < ApplicationController
  layout "sessions"

  require_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { render_rejection(:too_many_requests) }

  before_action :ensure_user_exists, only: :new

  def new
  end

  def create
    if (user = User.active.authenticate_by(email: params[:email], password: params[:password]))
      start_new_session_for(user)
      redirect_to post_authenticating_url
    else
      render_rejection(:unauthorized)
    end
  end

  def destroy
    reset_authentication
    redirect_to new_session_url
  end

  private

  def ensure_user_exists
    redirect_to first_run_url if User.none?
  end

  def render_rejection(status)
    flash.now[:alert] = t("sessions.create.#{status}")
    render :new, status: status
  end
end
