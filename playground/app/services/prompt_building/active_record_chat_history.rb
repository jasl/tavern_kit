# frozen_string_literal: true

module PromptBuilding
  # ActiveRecord-backed ChatHistory adapter.
  #
  # Wraps an ActiveRecord relation of Message records to implement
  # TavernKit's ChatHistory interface.
  #
  # For large histories, this class uses batched iteration to avoid loading
  # the entire conversation into memory at once.
  #
  # @example Usage
  #   history = PromptBuilding::ActiveRecordChatHistory.new(conversation.messages.ordered)
  #   history.each { |msg| puts msg.content }
  #
  # @example Copilot mode (flip roles for user with persona)
  #   history = PromptBuilding::ActiveRecordChatHistory.new(conversation.messages.ordered, copilot_speaker: user_participant)
  #   # Messages from copilot_speaker's character become "assistant"
  #   # Messages from other characters become "user"
  #
  class ActiveRecordChatHistory < ::TavernKit::ChatHistory::Base
    DEFAULT_BATCH_SIZE = 1_000

    # @param relation [ActiveRecord::Relation<Message>]
    # @param copilot_speaker [SpaceMembership, nil] if set, flip roles for copilot mode
    def initialize(relation, copilot_speaker: nil)
      @relation = relation
      @copilot_speaker = copilot_speaker
      @memoized_messages = nil
    end

    # Iterate over all messages as TavernKit::Prompt::Message objects.
    #
    # Note: We prefer batched iteration to avoid loading the entire relation at once.
    # We also preserve ordering from the relation; `find_each` is not suitable because
    # it ignores ORDER BY and forces primary key ordering.
    #
    # Messages marked as excluded_from_prompt are skipped (they remain visible
    # in the UI but are not sent to the LLM).
    #
    # @yield [TavernKit::Prompt::Message] each message
    # @return [Enumerator] if no block given
    def each(&block)
      return to_enum(:each) unless block

      relation = @relation

      # Prefer batched iteration when available (ActiveRecord).
      if relation.respond_to?(:in_batches)
        begin
          relation.in_batches(of: DEFAULT_BATCH_SIZE, cursor: %i[seq id], order: %i[asc asc]) do |batch|
            batch.each do |message|
              next if message.excluded_from_prompt?

              yield convert_message(message)
            end
          end
          return
        rescue ArgumentError
          # Fall back to normal iteration if cursor/order options aren't supported
          # (e.g., older Rails versions or non-standard relations).
        end
      end

      relation.each do |message|
        next if message.excluded_from_prompt?

        yield convert_message(message)
      end
    end

    # Get the number of messages.
    #
    # @return [Integer]
    def size
      # Keep `size` consistent with `each`, which skips messages that are excluded
      # from the prompt context.
      #
      # NOTE: We intentionally count *within* the relation's current window (including
      # any ORDER/LIMIT/OFFSET) and then filter out excluded rows, so `size` reflects
      # how many messages `each` will actually yield.
      if @relation.loaded?
        @relation.count { |message| !message.excluded_from_prompt? }
      else
        window = @relation
          .except(:includes, :preload, :eager_load)
          .reselect(:id, :excluded_from_prompt)

        ::Message
          .from(window, :windowed_messages)
          .where("windowed_messages.excluded_from_prompt = ?", false)
          .count
      end
    end

    # Get the last message(s).
    #
    # Optimized for ActiveRecord to avoid materializing the entire history.
    # Falls back to the base implementation when role flipping is enabled
    # (copilot mode), since roles are derived rather than stored.
    #
    # @param n [Integer, nil] number of messages to return (nil = single message)
    # @return [TavernKit::Prompt::Message, Array<TavernKit::Prompt::Message>, nil]
    def last(n = nil)
      return super if @copilot_speaker

      relation = @relation.where(excluded_from_prompt: false)

      if n.nil?
        record = relation.reorder(seq: :desc, id: :desc).first
        return nil unless record

        return convert_message(record)
      end

      n = n.to_i
      return [] if n <= 0

      ids = relation.reorder(seq: :desc, id: :desc).limit(n).select(:id)
      relation.where(id: ids).reorder(seq: :asc, id: :asc).map { |m| convert_message(m) }
    end

    # Count user messages in the history.
    #
    # Optimized for ActiveRecord when roles are not flipped.
    #
    # @return [Integer]
    def user_message_count
      return super if @copilot_speaker

      @relation.where(excluded_from_prompt: false, role: "user").count
    end

    # Count assistant messages in the history.
    #
    # Optimized for ActiveRecord when roles are not flipped.
    #
    # @return [Integer]
    def assistant_message_count
      return super if @copilot_speaker

      @relation.where(excluded_from_prompt: false, role: "assistant").count
    end

    # Count system messages in the history.
    #
    # Optimized for ActiveRecord when roles are not flipped.
    #
    # @return [Integer]
    def system_message_count
      return super if @copilot_speaker

      @relation.where(excluded_from_prompt: false, role: "system").count
    end

    # Convert to array.
    #
    # Memoized for the duration of the build to avoid repeated conversion when
    # multiple middleware/macro expansions call `history.to_a`.
    #
    # @return [Array<TavernKit::Prompt::Message>]
    def to_a
      @memoized_messages ||= super
    end

    # Append a message (not supported for ActiveRecord history).
    #
    # @param message [TavernKit::Prompt::Message]
    # @raise [NotImplementedError]
    def append(message)
      raise NotImplementedError, "ActiveRecordChatHistory is read-only. Use Message.create! to add messages."
    end

    # Clear all messages (not supported for ActiveRecord history).
    #
    # @raise [NotImplementedError]
    def clear
      raise NotImplementedError, "ActiveRecordChatHistory is read-only. Use conversation.messages.destroy_all to clear."
    end

    private

    # Convert an ActiveRecord Message to TavernKit::Prompt::Message.
    #
    # In copilot mode, roles are flipped:
    # - Messages from the copilot speaker's character become "assistant"
    # - Messages from other characters become "user"
    #
    # This ensures the prompt is built from the speaker's perspective.
    #
    # @param message [Message]
    # @return [TavernKit::Prompt::Message]
    def convert_message(message)
      role = determine_role(message)

      ::TavernKit::Prompt::Message.new(
        role: role,
        content: message.plain_text_content,
        name: message.sender_display_name,
        send_date: message.created_at&.to_i
      )
    end

    # Determine the role for a message, flipping if in copilot mode.
    #
    # @param message [Message]
    # @return [Symbol] :user or :assistant
    def determine_role(message)
      return message.role.to_sym unless @copilot_speaker

      # In copilot mode, flip roles based on who sent the message
      message_character_id = message.space_membership.character_id
      speaker_character_id = @copilot_speaker.character_id

      if message_character_id == speaker_character_id
        # Message is from the speaker's character (user with persona)
        # This should be "assistant" in the prompt
        :assistant
      else
        # Message is from other characters (AI characters)
        # This should be "user" in the prompt
        :user
      end
    end
  end
end
