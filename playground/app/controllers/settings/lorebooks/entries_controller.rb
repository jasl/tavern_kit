# frozen_string_literal: true

module Settings
  module Lorebooks
    # Controller for managing entries within a Lorebook.
    #
    # Provides CRUD operations for lorebook entries with support for
    # Turbo Stream updates for real-time editing.
    #
    class EntriesController < Settings::ApplicationController
      include ActionView::RecordIdentifier
      before_action :set_lorebook
      before_action :set_entry, only: %i[show edit update destroy]
      before_action :ensure_lorebook_unlocked, only: %i[new create update destroy reorder]

      # GET /settings/lorebooks/:lorebook_id/entries/:id
      # Show entry details (full view)
      def show
      end

      def new
        @entry = @lorebook.entries.build(
          uid: SecureRandom.uuid,
          position_index: (@lorebook.entries.maximum(:position_index) || -1) + 1
        )
      end

      def create
        @entry = @lorebook.entries.build(entry_params)

        if @entry.save
          redirect_to edit_settings_lorebook_path(@lorebook), notice: t("lorebook_entries.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @entry.update(entry_params)
          respond_to do |format|
            format.html { redirect_to edit_settings_lorebook_path(@lorebook), notice: t("lorebook_entries.updated") }
            format.turbo_stream do
              render turbo_stream: turbo_stream.action(
                :replace,
                dom_id(@entry),
                render_to_string(
                  partial: "settings/lorebooks/entries/entry_row",
                  locals: { entry: @entry, lorebook: @lorebook }
                ),
                method: "morph"
              )
            end
          end
        else
          error_message = @entry.errors.full_messages.to_sentence.presence ||
            t("lorebook_entries.update_failed", default: "Failed to update entry.")

          respond_to do |format|
            format.html do
              flash.now[:alert] = error_message
              render :edit, status: :unprocessable_entity
            end
            format.turbo_stream do
              render_toast_turbo_stream(message: error_message, type: "error", status: :unprocessable_entity)
            end
          end
        end
      end

      def destroy
        @entry.destroy!

        respond_to do |format|
          format.html { redirect_to edit_settings_lorebook_path(@lorebook), notice: t("lorebook_entries.deleted") }
          format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@entry)) }
        end
      end

      def reorder
        position_updates = params[:positions]
        return head :bad_request unless position_updates.is_a?(Array)

        LorebookEntry.transaction do
          position_updates.each_with_index do |entry_id, index|
            @lorebook.entries.where(id: entry_id).update_all(position_index: index)
          end
        end

        head :ok
      end

      private

      def set_lorebook
        @lorebook = Lorebook.find(params[:lorebook_id])
      end

      def set_entry
        @entry = @lorebook.entries.find(params[:id])
      end

      def entry_params
        permitted = params.require(:lorebook_entry).permit(
          :comment, :content, :enabled, :constant,
          :insertion_order, :position, :depth, :outlet,
          :selective, :selective_logic,
          :probability, :use_probability,
          :group, :group_weight, :group_override, :use_group_scoring,
          :sticky, :cooldown, :delay,
          :exclude_recursion, :prevent_recursion, :delay_until_recursion,
          :scan_depth, :case_sensitive, :match_whole_words,
          :match_persona_description, :match_character_description,
          :match_character_personality, :match_character_depth_prompt,
          :match_scenario, :match_creator_notes,
          :ignore_budget, :automation_id,
          :keys, :secondary_keys, :triggers
        )

        # Parse JSON array fields (submitted as JSON strings from keys-input controller)
        %i[keys secondary_keys triggers].each do |field|
          next unless permitted[field].is_a?(String)

          permitted[field] = JSON.parse(permitted[field])
        rescue JSON::ParserError
          permitted[field] = []
        end

        # Avoid mass-assigning "role" via strong params (Brakeman false-positive on "role").
        # We still support updating the entry role, but do it via explicit whitelist assignment.
        role = params.dig(:lorebook_entry, :role)
        if role.present? && LorebookEntry::ROLES.include?(role.to_s)
          permitted[:role] = role
        end

        permitted
      end

      def ensure_lorebook_unlocked
        return unless @lorebook.locked?

        error_message = t("lorebooks.locked", default: "Lorebook is locked.")

        respond_to do |format|
          format.html { redirect_to edit_settings_lorebook_path(@lorebook), alert: error_message }
          format.turbo_stream do
            render_toast_turbo_stream(message: error_message, type: "warning", duration: 5000, status: :forbidden)
          end
          format.json { head :forbidden }
        end
      end
    end
  end
end
