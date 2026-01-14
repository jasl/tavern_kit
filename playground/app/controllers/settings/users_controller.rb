# frozen_string_literal: true

module Settings
  class UsersController < Settings::ApplicationController
    before_action :set_user, only: %i[show toggle_status update_role]

    # GET /settings/users
    def index
      users = User.by_created_at.includes(:invited_by_code)
      set_page_and_extract_portion_from users, per_page: 20
    end

    # GET /settings/users/:id
    def show
    end

    # POST /settings/users/:id/toggle_status
    # Activate or deactivate a user
    def toggle_status
      # Prevent administrators from deactivating themselves
      if @user == Current.user
        redirect_to settings_users_path,
                    alert: t("users.toggle_status.cannot_deactivate_self",
                             default: "You cannot deactivate yourself.")
        return
      end

      if @user.active?
        @user.deactivate!
        notice = t("users.toggle_status.deactivated", default: "User has been deactivated.")
      else
        @user.activate!
        notice = t("users.toggle_status.activated", default: "User has been activated.")
      end

      redirect_to settings_users_path, notice: notice
    end

    # PATCH /settings/users/:id/role
    # Update a user's role
    def update_role
      # Prevent administrators from changing their own role
      if @user == Current.user
        redirect_to settings_users_path,
                    alert: t("users.update_role.cannot_change_own",
                             default: "You cannot change your own role.")
        return
      end

      new_role = params[:role]
      unless User::ROLES.include?(new_role)
        redirect_to settings_users_path,
                    alert: t("users.update_role.invalid_role", default: "Invalid role.")
        return
      end

      @user.update!(role: new_role)
      redirect_to settings_users_path,
                  notice: t("users.update_role.success",
                            default: "User role updated to %{role}.",
                            role: new_role.humanize)
    end

    private

    def set_user
      @user = User.find(params[:id])
    end
  end
end
