# frozen_string_literal: true

# Handles user registration via invite codes.
#
# Users access /join/:code with a valid invite code to create their account.
# The invite code is validated before showing the registration form.
#
class JoinController < ApplicationController
  skip_before_action :require_authentication, only: %i[show create]
  before_action :set_invite_code
  before_action :validate_invite_code
  before_action :redirect_if_logged_in

  # GET /join/:code
  # Show the registration form for an invite code
  def show
    @user = User.new
  end

  # POST /join/:code
  # Create a new user account using the invite code
  def create
    @user = User.new(user_params)
    @user.invited_by_code = @invite_code

    if @user.save
      # Create a session for the new user
      session = @user.sessions.create!(
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        last_active_at: Time.current
      )
      cookies.signed.permanent[:session_token] = { value: session.token, httponly: true }

      redirect_to root_path, notice: t("join.success", default: "Welcome! Your account has been created.")
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_invite_code
    @invite_code = InviteCode.find_by(code: params[:code])
  end

  def validate_invite_code
    if @invite_code.nil?
      redirect_to root_path, alert: t("join.invalid_code", default: "Invalid invite code.")
    elsif !@invite_code.valid_for_use?
      if @invite_code.expired?
        redirect_to root_path, alert: t("join.code_expired", default: "This invite code has expired.")
      elsif @invite_code.exhausted?
        redirect_to root_path, alert: t("join.code_exhausted", default: "This invite code has reached its usage limit.")
      else
        redirect_to root_path, alert: t("join.code_invalid", default: "This invite code is no longer valid.")
      end
    end
  end

  def redirect_if_logged_in
    redirect_to root_path, notice: t("join.already_logged_in", default: "You are already logged in.") if Current.user.present?
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end
end
