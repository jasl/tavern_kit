# frozen_string_literal: true

module Lorebooks
  # User-facing controller for managing entries within a Lorebook.
  #
  # Provides CRUD operations for lorebook entries with support for
  # Turbo Stream updates for real-time editing.
  #
  # Only allows editing entries for user-owned lorebooks that are not locked.
  # Global lorebooks (user_id = nil) are read-only.
  #
  class EntriesController < ApplicationController
    before_action :set_lorebook
    before_action :set_entry, only: %i[show edit update destroy]
    before_action :require_editable, except: %i[show]

    # GET /lorebooks/:lorebook_id/entries/:id
    # Show entry details (read-only, available to all users with lorebook access)
    def show
    end

    # GET /lorebooks/:lorebook_id/entries/new
    def new
      @entry = @lorebook.entries.build(
        uid: SecureRandom.uuid,
        position_index: (@lorebook.entries.maximum(:position_index) || -1) + 1
      )
    end

    # POST /lorebooks/:lorebook_id/entries
    def create
      @entry = @lorebook.entries.build(entry_params)

      if @entry.save
        redirect_to edit_lorebook_path(@lorebook), notice: t("lorebook_entries.created", default: "Entry created.")
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /lorebooks/:lorebook_id/entries/:id/edit
    def edit
    end

    # PATCH/PUT /lorebooks/:lorebook_id/entries/:id
    def update
      if @entry.update(entry_params)
        redirect_to edit_lorebook_path(@lorebook), notice: t("lorebook_entries.updated", default: "Entry updated.")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /lorebooks/:lorebook_id/entries/:id
    def destroy
      @entry.destroy!

      respond_to do |format|
        format.html { redirect_to edit_lorebook_path(@lorebook), notice: t("lorebook_entries.deleted", default: "Entry deleted.") }
        format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@entry)) }
      end
    end

    # PATCH /lorebooks/:lorebook_id/entries/reorder
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
      @lorebook = Lorebook.accessible_to(Current.user).find(params[:lorebook_id])
    end

    def set_entry
      @entry = @lorebook.entries.find(params[:id])
    end

    def require_editable
      return if editable?(@lorebook)

      redirect_to lorebook_path(@lorebook),
                  alert: t("lorebooks.not_editable", default: "You cannot edit this lorebook.")
    end

    def editable?(lorebook)
      lorebook.user_id == Current.user&.id && !lorebook.locked?
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
  end
end
