# frozen_string_literal: true

module Settings
  class InviteCodesController < Settings::ApplicationController
    before_action :set_invite_code, only: %i[show destroy regenerate]

    # GET /settings/invite_codes
    def index
      invite_codes = InviteCode.ordered.includes(:created_by)
      set_page_and_extract_portion_from invite_codes, per_page: 20
    end

    # GET /settings/invite_codes/new
    def new
      @invite_code = InviteCode.new
    end

    # GET /settings/invite_codes/:id
    def show
      @users = @invite_code.users.by_created_at.limit(10)
    end

    # POST /settings/invite_codes
    def create
      @invite_code = InviteCode.new(invite_code_params)
      @invite_code.created_by = Current.user

      if @invite_code.save
        redirect_to settings_invite_code_path(@invite_code),
                    notice: t("invite_codes.create.success", default: "Invite code created successfully.")
      else
        flash.now[:alert] = @invite_code.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    # DELETE /settings/invite_codes/:id
    def destroy
      @invite_code.destroy!
      redirect_to settings_invite_codes_path,
                  notice: t("invite_codes.destroy.success", default: "Invite code deleted.")
    end

    # POST /settings/invite_codes/:id/regenerate
    # Generate a new code while keeping the same record (for security purposes)
    def regenerate
      old_code = @invite_code.code
      new_code = InviteCode.send(:generate_unique_code)
      @invite_code.update!(code: new_code)

      redirect_to settings_invite_code_path(@invite_code),
                  notice: t("invite_codes.regenerate.success", default: "Invite code regenerated.")
    end

    private

    def set_invite_code
      @invite_code = InviteCode.find(params[:id])
    end

    def invite_code_params
      params.fetch(:invite_code, {}).permit(:note, :max_uses, :expires_at)
    end
  end
end
