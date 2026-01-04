# frozen_string_literal: true

class FirstRunsController < ApplicationController
  layout "sessions"

  allow_unauthenticated_access

  before_action :prevent_repeats

  def show
    @user = User.new
  end

  def create
    user = FirstRun.create!(user_params)
    start_new_session_for(user)

    redirect_to root_url
  rescue ActiveRecord::RecordNotUnique
    redirect_to root_url
  rescue ActiveRecord::RecordInvalid => e
    @user = e.record
    flash.now[:alert] = @user.errors.full_messages.to_sentence
    render :show, status: :unprocessable_entity
  end

  private

  def prevent_repeats
    redirect_to root_url if Setting.get("site.initialized", false)
  end

  def user_params
    params.require(:user).permit(:name, :email, :password)
  end
end
