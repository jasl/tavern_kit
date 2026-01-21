# frozen_string_literal: true

# TurnScheduler is the unified conversation scheduling system.
#
# This is the single source of truth for determining who speaks and when.
# It replaces the old ConversationScheduler with a cleaner, command-based architecture.
#
# ## Architecture
#
# - **Commands**: Mutate state (StartRound, AdvanceTurn, ScheduleSpeaker, etc.)
# - **Queries**: Read state without mutation (NextSpeaker, QueuePreview)
# - **State**: Value objects representing current state (RoundState)
# - **Broadcasts**: Handle real-time updates to connected clients
#
# ## Design Principles
#
# 1. **Single Source of Truth**: All scheduling state is persisted in round tables
# 2. **Command Pattern**: Each operation is a distinct, testable command object
# 3. **Explicit State Machine**: States are explicit strings, not derived from data
# 4. **Unidirectional Data Flow**: Message → AdvanceTurn → ScheduleSpeaker → Run
#
# ## Usage
#
# ```ruby
# # Start a round
# TurnScheduler::Commands::StartRound.execute(conversation: conversation)
#
# # Advance after message
# TurnScheduler::Commands::AdvanceTurn.execute(
#   conversation: conversation,
#   speaker_membership: message.space_membership
# )
#
# # Get next speaker prediction
# speaker = TurnScheduler::Queries::NextSpeaker.execute(conversation: conversation)
#
# # Get queue preview for UI
# queue = TurnScheduler::Queries::QueuePreview.execute(conversation: conversation)
# ```
#
module TurnScheduler
  # Scheduling states
  STATES = %w[idle ai_generating paused failed].freeze

  class << self
    # Start a new round of conversation.
    #
    # @param conversation [Conversation]
    # @return [Boolean] true if round started successfully
    def start_round!(conversation)
      Commands::StartRound.execute(conversation: conversation).payload[:started]
    end

    # Advance to next turn after a message is created.
    #
    # @param conversation [Conversation]
    # @param speaker_membership [SpaceMembership] who just created a message
    # @param message_id [Integer, nil] the message that triggered advancement (for activation semantics)
    # @return [Boolean] true if turn was advanced
    def advance_turn!(conversation, speaker_membership, message_id: nil)
      Commands::AdvanceTurn.execute(conversation: conversation, speaker_membership: speaker_membership, message_id: message_id)
        .payload[:advanced]
    end

    # Stop the current round.
    #
    # @param conversation [Conversation]
    # @return [Boolean] true if stopped
    def stop!(conversation)
      Commands::StopRound.execute(conversation: conversation)
    end

    # Handle a failed generation.
    #
    # @param conversation [Conversation]
    # @param run [ConversationRun] the failed run
    # @param error [Hash, Exception, String] the error
    # @return [Boolean] true if handled
    def handle_failure!(conversation, run, error)
      Commands::HandleFailure.execute(conversation: conversation, run: run, error: error).payload[:handled]
    end

    # Get the current state.
    #
    # @param conversation [Conversation]
    # @return [State::RoundState]
    def state(conversation)
      State::RoundState.new(conversation)
    end

    # Get the next speaker.
    #
    # @param conversation [Conversation]
    # @param previous_speaker [SpaceMembership, nil]
    # @param allow_self [Boolean]
    # @return [SpaceMembership, nil]
    def next_speaker(conversation, previous_speaker: nil, allow_self: true)
      Queries::NextSpeaker.execute(
        conversation: conversation,
        previous_speaker: previous_speaker,
        allow_self: allow_self
      )
    end

    # Get queue preview for UI.
    #
    # @param conversation [Conversation]
    # @param limit [Integer]
    # @return [Array<SpaceMembership>]
    def queue_preview(conversation, limit: 10)
      Queries::QueuePreview.execute(conversation: conversation, limit: limit)
    end
  end
end
