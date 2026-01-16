# frozen_string_literal: true

module Settings
  module Characters
    # Controller for managing embedded lorebook entries (character_book.entries) in Settings.
    #
    # Provides CRUD operations for entries stored in the character's embedded character_book.
    # Unlike LorebookEntry (database-backed), these entries are stored in the character's
    # `data` JSON column and require special handling for persistence.
    #
    class EmbeddedLorebookEntriesController < Settings::ApplicationController
      include ActionView::RecordIdentifier
      # Valid roles for embedded entries
      VALID_ROLES = %w[system user assistant].freeze

      before_action :set_character
      before_action :set_entry, only: %i[edit update destroy]
      before_action :ensure_character_unlocked, only: %i[new create edit update destroy reorder]

      # GET /settings/characters/:character_id/embedded_lorebook_entries/new
      def new
        @entry = EmbeddedLorebookEntryPresenter.new(default_entry_attributes, character: @character, mode: :settings)
      end

      # POST /settings/characters/:character_id/embedded_lorebook_entries
      def create
        entry_attrs = entry_params_to_hash

        # Add to embedded entries
        entries = embedded_entries.dup
        entries << entry_attrs

        if save_embedded_entries(entries)
          redirect_to edit_settings_character_path(@character),
                      notice: t("embedded_lorebook_entries.created", default: "Entry created.")
        else
          @entry = EmbeddedLorebookEntryPresenter.new(entry_attrs, character: @character, mode: :settings)
          flash.now[:alert] = @character.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity
        end
      end

      # GET /settings/characters/:character_id/embedded_lorebook_entries/:id/edit
      def edit
      end

      # PATCH/PUT /settings/characters/:character_id/embedded_lorebook_entries/:id
      def update
        entry_attrs = entry_params_to_hash
        # Remove auto-generated ID - we want to keep the existing entry's ID
        entry_attrs.delete(:id)

        # Merge updates into existing entry (preserves unsubmitted fields like keys, content)
        entries = embedded_entries.map do |e|
          e[:id].to_s == params[:id] ? e.merge(entry_attrs) : e
        end

        if save_embedded_entries(entries)
          respond_to do |format|
            format.html do
              redirect_to edit_settings_character_path(@character),
                          notice: t("embedded_lorebook_entries.updated", default: "Entry updated.")
            end
            format.turbo_stream do
              # Reload the entry from the freshly saved character
              @character.reload
              updated_entry = embedded_entries.find { |e| e[:id].to_s == params[:id] }
              @entry = EmbeddedLorebookEntryPresenter.new(updated_entry, character: @character, mode: :settings)
              render turbo_stream: turbo_stream.action(
                :replace,
                @entry.dom_id,
                render_to_string(
                  partial: "characters/embedded_lorebook_entries/inline_entry_row",
                  locals: { presenter: @entry, character: @character, mode: :settings, editable: true }
                ),
                method: "morph"
              )
            end
          end
        else
          error_message = @character.errors.full_messages.to_sentence.presence ||
            t("embedded_lorebook_entries.update_failed", default: "Failed to update entry.")

          @entry = EmbeddedLorebookEntryPresenter.new(entry_attrs.merge(id: params[:id]), character: @character, mode: :settings)

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

      # DELETE /settings/characters/:character_id/embedded_lorebook_entries/:id
      def destroy
        entries = embedded_entries.reject { |e| e[:id].to_s == params[:id] }

        if save_embedded_entries(entries)
          respond_to do |format|
            format.html do
              redirect_to edit_settings_character_path(@character),
                          notice: t("embedded_lorebook_entries.deleted", default: "Entry deleted.")
            end
            format.turbo_stream do
              if params[:inline].present?
                @character.reload
                render turbo_stream: turbo_stream.action(
                  :replace,
                  dom_id(@character, :embedded_lorebook_entries),
                  render_to_string(
                    partial: "characters/embedded_lorebook_entries/inline_entries_section",
                    locals: { character: @character, mode: :settings }
                  ),
                  method: "morph"
                )
              else
                redirect_to edit_settings_character_path(@character), status: :see_other
              end
            end
          end
        else
          error_message = @character.errors.full_messages.to_sentence.presence ||
            t("embedded_lorebook_entries.delete_failed", default: "Failed to delete entry.")

          respond_to do |format|
            format.html { redirect_to edit_settings_character_path(@character), alert: error_message }
            format.turbo_stream do
              render_toast_turbo_stream(message: error_message, type: "error", status: :unprocessable_entity)
            end
          end
        end
      end

      # PATCH /settings/characters/:character_id/embedded_lorebook_entries/reorder
      def reorder
        position_updates = params[:positions]
        return head :bad_request unless position_updates.is_a?(Array)

        entries = embedded_entries
        entry_by_id = entries.index_by { |e| e[:id].to_s }
        seen_ids = {}

        ordered_entries = position_updates.filter_map do |entry_id|
          id = entry_id.to_s
          next if id.blank? || seen_ids.key?(id)

          seen_ids[id] = true
          entry_by_id[id]
        end

        # Never drop entries if the client sends a partial/invalid list.
        ordered_entries.concat(entries.reject { |e| seen_ids.key?(e[:id].to_s) })

        # Update insertion_order based on position
        ordered_entries.each_with_index do |entry, index|
          entry[:insertion_order] = index * 10
        end

        if save_embedded_entries(ordered_entries)
          respond_to do |format|
            format.html { head :ok }
            format.json { head :ok }
            format.turbo_stream do
              @character.reload
              render turbo_stream: turbo_stream.action(
                :replace,
                dom_id(@character, :embedded_lorebook_entries),
                render_to_string(
                  partial: "characters/embedded_lorebook_entries/inline_entries_section",
                  locals: { character: @character, mode: :settings }
                ),
                method: "morph"
              )
            end
          end
        else
          error_message = @character.errors.full_messages.to_sentence.presence ||
            t("embedded_lorebook_entries.reorder_failed", default: "Failed to reorder entries.")

          respond_to do |format|
            format.html { head :unprocessable_entity }
            format.json { head :unprocessable_entity }
            format.turbo_stream do
              render_toast_turbo_stream(message: error_message, type: "error", status: :unprocessable_entity)
            end
          end
        end
      end

      private

      def set_character
        @character = Character.find(params[:character_id])
      end

      def set_entry
        entry_hash = embedded_entries.find { |e| e[:id].to_s == params[:id] }
        raise ActiveRecord::RecordNotFound unless entry_hash

        @entry = EmbeddedLorebookEntryPresenter.new(entry_hash, character: @character, mode: :settings)
      end

      def ensure_character_unlocked
        return unless @character.locked?

        error_message = t("characters.locked", default: "Character is locked.")

        respond_to do |format|
          format.html do
            redirect_to edit_settings_character_path(@character), alert: error_message
          end
          format.turbo_stream do
            render_toast_turbo_stream(message: error_message, type: "warning", duration: 5000, status: :forbidden)
          end
          format.json { head :forbidden }
        end
      end

      # Get embedded entries array from character data
      def embedded_entries
        book = @character.data&.character_book
        return [] unless book

        entries = book.respond_to?(:entries) ? book.entries : book[:entries]
        Array(entries).map do |entry|
          entry.is_a?(Hash) ? entry.deep_symbolize_keys : entry.to_h.deep_symbolize_keys
        end
      end

      # Save updated entries to character's character_book
      def save_embedded_entries(entries)
        current_data = @character.data&.to_h&.deep_symbolize_keys || {}
        current_book = current_data[:character_book]&.to_h&.deep_symbolize_keys || {}

        current_book[:entries] = entries.map(&:deep_symbolize_keys)
        current_data[:character_book] = current_book

        @character.update(data: current_data, file_sha256: nil)
      end

      # Convert params to entry hash
      def entry_params_to_hash
        permitted = params.require(:character_book_entry).permit(
          :comment, :content, :enabled, :constant, :use_regex,
          :position, :insertion_order, :depth, :outlet,
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
          :keys, :secondary_keys
        )

        # Avoid mass-assigning "role" via strong params (Brakeman false-positive on "role").
        # We still support updating the entry role, but do it via explicit whitelist assignment.
        role = params.dig(:character_book_entry, :role)
        if role.present? && VALID_ROLES.include?(role.to_s)
          permitted[:role] = role
        end

        # Parse JSON array fields (only if present in params)
        %i[keys secondary_keys].each do |field|
          next unless permitted.key?(field)

          if permitted[field].is_a?(String)
            begin
              permitted[field] = JSON.parse(permitted[field])
            rescue JSON::ParserError
              permitted[field] = []
            end
          end

          # Ensure arrays are proper arrays (only if field was submitted)
          permitted[field] = Array(permitted[field]).map(&:to_s).reject(&:blank?)
        end

        # Convert string booleans
        %i[enabled constant use_regex selective use_probability group_override use_group_scoring
           exclude_recursion prevent_recursion case_sensitive match_whole_words
           match_persona_description match_character_description match_character_personality
           match_character_depth_prompt match_scenario match_creator_notes ignore_budget].each do |field|
          permitted[field] = coerce_bool(permitted[field]) if permitted.key?(field)
        end

        # Convert integers
        %i[insertion_order depth probability group_weight sticky cooldown delay
           delay_until_recursion scan_depth].each do |field|
          permitted[field] = permitted[field].to_i if permitted[field].present?
        end

        # Generate ID for new entries
        permitted[:id] ||= SecureRandom.uuid

        permitted.to_h.deep_symbolize_keys
      end

      def default_entry_attributes
        {
          keys: [],
          content: "",
          enabled: true,
          constant: false,
          use_regex: false,
          position: "before_char_defs",
          insertion_order: (embedded_entries.map { |e| e[:insertion_order] || 0 }.max || 0) + 100,
        }
      end

      def coerce_bool(value)
        return true if value == true || value == "1" || value == "true"
        return false if value == false || value == "0" || value == "false"

        value
      end
    end
  end
end
