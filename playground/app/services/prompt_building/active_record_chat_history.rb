# frozen_string_literal: true

module PromptBuilding
  # ActiveRecord-backed ChatHistory adapter.
  #
  # Wraps an ActiveRecord relation of Message records to implement
  # TavernKit's ChatHistory interface without loading all messages
  # into memory at once.
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
    # @param relation [ActiveRecord::Relation<Message>]
    # @param copilot_speaker [SpaceMembership, nil] if set, flip roles for copilot mode
    def initialize(relation, copilot_speaker: nil)
      @relation = relation
      @copilot_speaker = copilot_speaker
    end

    # Iterate over all messages as TavernKit::Prompt::Message objects.
    #
    # Note: We use `each` instead of `find_each` to preserve the ordering
    # from the relation (find_each ignores ORDER BY and orders by primary key).
    #
    # Messages marked as excluded_from_prompt are skipped (they remain visible
    # in the UI but are not sent to the LLM).
    #
    # @yield [TavernKit::Prompt::Message] each message
    # @return [Enumerator] if no block given
    def each(&block)
      return to_enum(:each) unless block

      @relation.each do |message|
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
