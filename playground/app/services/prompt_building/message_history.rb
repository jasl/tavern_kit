# frozen_string_literal: true

module PromptBuilding
  # ActiveRecord-backed chat history adapter for prompt building.
  #
  # This is a TavernKit-facing *data source* used during prompt building, not a general-purpose
  # message container.
  #
  # It is intentionally read-only and tries to keep database load predictable:
  # - Batched iteration (cursor-based) when available.
  # - SQL-based counts for turn-count helpers.
  # - Defensive preloading to avoid N+1 when callers forget to include associations.
  #
  # @example
  #   history = PromptBuilding::MessageHistory.new(conversation.messages.ordered)
  #   history.each { |msg| puts msg.content }
  #
  class MessageHistory < ::TavernKit::ChatHistory::Base
    DEFAULT_BATCH_SIZE = 1_000

    # @param relation [ActiveRecord::Relation<Message>]
    # @param batch_size [Integer] batch size for DB iteration (when supported)
    def initialize(relation, batch_size: DEFAULT_BATCH_SIZE)
      @relation = relation
      @batch_size = batch_size.to_i
      @memoized_messages = nil
    end

    # Iterate over all messages as TavernKit::Prompt::Message objects.
    #
    # Messages that are not included in the prompt are skipped (they remain visible
    # in the UI but are not sent to the LLM).
    #
    # @yield [TavernKit::Prompt::Message] each message
    # @return [Enumerator] if no block given
    def each(&block)
      return to_enum(:each) unless block

      # Preload associations once at the outer level to avoid repeated queries in batches
      relation = @relation
      relation = relation.with_participant if relation.respond_to?(:with_participant)

      # Prefer batched iteration when available (ActiveRecord).
      if relation.respond_to?(:in_batches)
        begin
          # Note: in_batches returns a fresh relation for each batch, but since we already
          # applied with_participant above, the association preloading is already configured.
          # We don't need to execute with_participant again inside the batch loop.
          relation.in_batches(of: effective_batch_size, cursor: %i[seq id], order: %i[asc asc]) do |batch|
            batch.each do |message|
              next unless message.visibility_normal?

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
        next unless message.visibility_normal?

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
        @relation.count { |message| message.visibility_normal? }
      else
        window = @relation
          .except(:includes, :preload, :eager_load)
          .reselect(:id, :visibility)

        ::Message
          .from(window, :windowed_messages)
          .where("windowed_messages.visibility = ?", "normal")
          .count
      end
    end

    # Get the last message(s).
    #
    # Optimized for ActiveRecord to avoid materializing the entire history.
    #
    # @param n [Integer, nil] number of messages to return (nil = single message)
    # @return [TavernKit::Prompt::Message, Array<TavernKit::Prompt::Message>, nil]
    def last(n = nil)
      relation = @relation.included_in_prompt
      relation = relation.with_participant if relation.respond_to?(:with_participant)

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
    # @return [Integer]
    def user_message_count
      relation = relation_for_counts
      relation.where(role: "user").count
    end

    # Count assistant messages in the history.
    #
    # @return [Integer]
    def assistant_message_count
      relation = relation_for_counts
      relation.where(role: "assistant").count
    end

    # Count system messages in the history.
    #
    # @return [Integer]
    def system_message_count
      relation_for_counts.where(role: "system").count
    end

    # Convert to array.
    #
    # Memoized for the duration of the build to avoid repeated conversion when
    # multiple execute sites execute `history.to_a`.
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
      raise NotImplementedError, "MessageHistory is read-only. Use Message.create! to add messages."
    end

    # Clear all messages (not supported for ActiveRecord history).
    #
    # @raise [NotImplementedError]
    def clear
      raise NotImplementedError, "MessageHistory is read-only. Use conversation.messages.destroy_all to clear."
    end

    private

    def effective_batch_size
      @batch_size.positive? ? @batch_size : DEFAULT_BATCH_SIZE
    end

    def relation_for_counts
      @relation
        .except(:includes, :preload, :eager_load)
        .included_in_prompt
    end

    # Convert an ActiveRecord Message to TavernKit::Prompt::Message.
    #
    # @param message [Message]
    # @return [TavernKit::Prompt::Message]
    def convert_message(message)
      ::TavernKit::Prompt::Message.new(
        role: message.role.to_sym,
        content: message.plain_text_content,
        name: message.sender_display_name,
        send_date: message.created_at&.to_i
      )
    end
  end
end
