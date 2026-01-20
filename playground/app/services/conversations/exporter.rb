# frozen_string_literal: true

module Conversations
  # Exports conversation in JSONL or TXT format.
  #
  # JSONL format is designed to be re-importable:
  # - First line: Metadata header with conversation info and space settings
  # - Subsequent lines: Messages with all swipes and metadata
  #
  # TXT format is human-readable:
  # - Timestamps and speaker names
  # - Clear separation between messages
  #
  # @example Export to JSONL
  #   Conversations::Exporter.to_jsonl(conversation)
  #
  # @example Export to TXT
  #   Conversations::Exporter.to_txt(conversation)
  #
  class Exporter
    class << self
      # Export conversation to JSONL format.
      #
      # @param conversation [Conversation] the conversation to export
      # @return [String] JSONL content (one JSON object per line)
      def to_jsonl(conversation)
        lines = []

        # Header line with metadata
        lines << JSON.generate(build_header(conversation))

        # Message lines
        messages = conversation.messages
          .scheduler_visible
          .includes(:space_membership, :message_swipes, message_swipes: :text_content, space_membership: %i[user character])
          .order(:seq, :id)

        messages.each do |message|
          lines << JSON.generate(build_message(message))
        end

        lines.join("\n")
      end

      # Export conversation to TXT format.
      #
      # @param conversation [Conversation] the conversation to export
      # @return [String] Human-readable transcript
      def to_txt(conversation)
        lines = []

        # Header
        lines << "=" * 60
        lines << "Conversation: #{conversation.title}"
        lines << "Created: #{conversation.created_at.strftime('%Y-%m-%d %H:%M:%S %Z')}"
        lines << "Exported: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"

        if conversation.authors_note.present?
          lines << ""
          lines << "Author's Note:"
          lines << conversation.authors_note
        end

        lines << "=" * 60
        lines << ""

        # Messages
        messages = conversation.messages
          .scheduler_visible
          .includes(:space_membership, space_membership: %i[user character])
          .order(:seq, :id)

        messages.each do |message|
          lines << format_message_txt(message)
          lines << ""
        end

        lines.join("\n")
      end

      private

      def build_header(conversation)
        space = conversation.space

        {
          format_version: 1,
          exported_at: Time.current.iso8601,
          conversation: {
            id: conversation.id,
            title: conversation.title,
            kind: conversation.kind,
            visibility: conversation.visibility,
            authors_note: conversation.authors_note,
            authors_note_position: conversation.authors_note_position,
            authors_note_depth: conversation.authors_note_depth,
            authors_note_role: conversation.authors_note_role,
            created_at: conversation.created_at.iso8601,
            updated_at: conversation.updated_at.iso8601,
          },
          # Include tree relationship info for full context
          tree: {
            root_conversation_id: conversation.root_conversation_id,
            parent_conversation_id: conversation.parent_conversation_id,
            forked_from_message_id: conversation.forked_from_message_id,
          },
          # Space settings snapshot (for context, not necessarily for re-import)
          space_settings: {
            name: space.name,
            reply_order: space.reply_order,
            card_handling_mode: space.card_handling_mode,
            auto_without_human_delay_ms: space.auto_without_human_delay_ms,
            user_turn_debounce_ms: space.user_turn_debounce_ms,
          },
        }
      end

      def build_message(message)
        {
          id: message.id,
          seq: message.seq,
          role: message.role,
          content: message.content,
          excluded_from_prompt: message.visibility_excluded?,
          visibility: message.visibility,
          created_at: message.created_at.iso8601,
          updated_at: message.updated_at.iso8601,
          generation_status: message.generation_status,
          metadata: message.metadata,
          # Speaker info
          speaker: {
            id: message.space_membership_id,
            display_name: message.sender_display_name,
            kind: message.space_membership.kind,
            character_id: message.space_membership.character_id,
            user_id: message.space_membership.user_id,
          },
          # All swipes (important for full export)
          swipes: message.message_swipes.map do |swipe|
            {
              position: swipe.position,
              content: swipe.content,
              is_active: swipe.id == message.active_message_swipe_id,
              created_at: swipe.created_at.iso8601,
              metadata: swipe.metadata,
            }
          end,
          active_swipe_position: message.active_message_swipe&.position,
        }
      end

      def format_message_txt(message)
        timestamp = message.created_at.strftime("%Y-%m-%d %H:%M:%S")
        speaker = message.sender_display_name
        role_indicator = case message.role
        when "system" then "[SYSTEM]"
        when "assistant" then "[AI]"
        when "user" then "[USER]"
        else "[#{message.role.upcase}]"
        end

        excluded_marker = message.visibility_excluded? ? " [EXCLUDED]" : ""

        lines = []
        lines << "[#{timestamp}] #{speaker} #{role_indicator}#{excluded_marker}"
        lines << "-" * 40
        lines << (message.content.presence || "(empty)")

        # Show swipe info if multiple swipes exist
        if message.message_swipes_count > 1
          active_pos = message.active_message_swipe&.position.to_i + 1
          total = message.message_swipes_count
          lines << ""
          lines << "(Swipe #{active_pos}/#{total})"
        end

        lines.join("\n")
      end
    end
  end
end
