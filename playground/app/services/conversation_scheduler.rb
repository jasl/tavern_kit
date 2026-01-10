# frozen_string_literal: true

# Unified conversation scheduler that manages ALL turn management.
#
# This is the single source of truth for determining who speaks and when.
# All participants (AI characters, Copilot humans, regular humans) are in one queue.
#
# ## Design Principles
#
# 1. **Single Queue**: All participants in one ordered queue
# 2. **Message-Driven Advancement**: Message `after_create_commit` triggers turn advancement
# 3. **Natural Human Blocking**: Scheduler waits for human message creation
# 4. **Auto Mode Skip**: Delayed job skips unresponsive humans in auto mode
#
# ## Queue State Structure (stored in conversation.turn_queue_state)
#
# {
#   "queue": [membership_id1, membership_id2, ...],  # Ordered speaker IDs
#   "position": 0,                                    # Current speaker index
#   "spoken": [membership_id1, ...],                  # Who has spoken this round
#   "round_id": "uuid"                                # Unique round identifier
# }
#
# ## Lifecycle
#
# 1. User enables auto mode or conversation starts → `start_round!`
# 2. Scheduler calculates turn order → `schedule_current_turn!`
# 3. For AI/Copilot: creates ConversationRun
# 4. For Human in auto mode: schedules skip timeout job
# 5. For Human without auto mode: waits for message
# 6. Message created → `advance_turn!` → moves to next speaker
# 7. If round complete → check if new round needed
#
class ConversationScheduler
  HUMAN_SKIP_DELAY_SECONDS = 10 # How long to wait for human before skipping in auto mode

  attr_reader :conversation, :space

  def initialize(conversation)
    @conversation = conversation
    @space = conversation.space
  end

  # ============================================================================
  # Public API
  # ============================================================================

  # Start a new round - calculate queue, reset state.
  #
  # Call this when:
  # - Auto mode is enabled
  # - Copilot is enabled and no round active
  # - User manually triggers a new round
  #
  # @param skip_to_ai [Boolean] if true, skip humans without copilot to find first AI speaker
  # @return [void]
  def start_round!(skip_to_ai: false)
    # Cancel any existing queued runs to avoid unique constraint violation
    cancel_existing_queued_runs!

    queue = build_ordered_queue
    return if queue.empty?

    round_id = SecureRandom.uuid
    position = 0
    spoken = []

    # When auto mode starts, skip humans without copilot to get to the first AI speaker
    # This makes the experience more natural - AI starts talking immediately
    if skip_to_ai && auto_mode_active?
      while position < queue.length
        speaker = queue[position]
        break if speaker.can_auto_respond? # Found an AI or Copilot user
        spoken << speaker.id # Mark skipped humans as "spoken" (they didn't speak, but we moved past them)
        position += 1
      end
    end

    # If we skipped everyone, no AI available
    return if position >= queue.length

    update_state!(
      queue: queue.map(&:id),
      position: position,
      spoken: spoken,
      round_id: round_id
    )

    broadcast_queue_update
    schedule_current_turn!
  end

  # Advance to the next turn after a message is created.
  #
  # Called by Message `after_create_commit`. This is the primary driver
  # of the scheduler - each message creation advances the queue.
  #
  # If no active round exists but the conversation allows auto-responses
  # (reply_order != "manual"), this will start a new round and schedule
  # the next speaker.
  #
  # @param speaker_membership [SpaceMembership] the speaker who just created a message
  # @return [void]
  def advance_turn!(speaker_membership)
    state = load_state

    # If no active round, check if we should start one
    if state.empty?
      return unless should_auto_schedule_response?

      # Start a new round with this speaker already marked as spoken
      start_round_after_message!(speaker_membership)
      return
    end

    # Mark this speaker as having spoken
    spoken = state["spoken"] || []
    spoken << speaker_membership.id unless spoken.include?(speaker_membership.id)

    # Increment turns count
    conversation.increment!(:turns_count)

    # Decrement resources for the speaker
    decrement_speaker_resources!(speaker_membership)

    # Move to next position
    position = (state["position"] || 0) + 1
    queue = state["queue"] || []

    if position >= queue.length
      # Round complete - check if we should start a new round
      handle_round_complete!(state)
    else
      # Continue with next speaker
      update_state!(state.merge("position" => position, "spoken" => spoken))
      schedule_current_turn!
    end

    broadcast_queue_update
  end

  # Get the current speaker (the one whose turn it is).
  #
  # @return [SpaceMembership, nil] current speaker, or nil if waiting/no round
  def current_speaker
    state = load_state
    return nil if state.empty?

    queue = state["queue"] || []
    position = state["position"] || 0
    membership_id = queue[position]
    return nil unless membership_id

    space.space_memberships.find_by(id: membership_id)
  end

  # Schedule the current speaker's turn.
  #
  # - For AI/Copilot: Creates a ConversationRun
  # - For Human + Auto mode: Schedules skip timeout job
  # - For Human only: Does nothing (waits for message)
  #
  # @return [void]
  def schedule_current_turn!
    speaker = current_speaker
    return unless speaker

    if speaker.can_auto_respond?
      # AI or Copilot user - create a run
      create_run_for_speaker!(speaker)
    elsif auto_mode_active?
      # Human in auto mode - schedule skip timeout
      schedule_human_skip!(speaker)
    end
    # Human without auto mode - just wait for them to send a message
  end

  # Skip a human speaker if eligible (used by HumanTurnTimeoutJob).
  #
  # Only skips if:
  # - Still in the same round (round_id matches)
  # - Human hasn't spoken yet
  # - Auto mode is still active
  #
  # @param membership_id [Integer] the human membership to potentially skip
  # @param round_id [String] the round ID when the skip was scheduled
  # @return [Boolean] true if skipped, false otherwise
  def skip_human_if_eligible!(membership_id, round_id)
    state = load_state
    return false if state.empty?
    return false if state["round_id"] != round_id
    return false unless auto_mode_active?

    spoken = state["spoken"] || []
    return false if spoken.include?(membership_id)

    # Verify it's still this human's turn
    queue = state["queue"] || []
    position = state["position"] || 0
    return false if queue[position] != membership_id

    # Skip this human - advance without message
    Rails.logger.info "[ConversationScheduler] Skipping human #{membership_id} due to timeout"

    position += 1
    if position >= queue.length
      handle_round_complete!(state)
    else
      update_state!(state.merge("position" => position))
      schedule_current_turn!
    end

    broadcast_queue_update
    true
  end

  # Recalculate queue mid-round (member added/removed/changed).
  #
  # Preserves spoken history and adjusts position if needed.
  #
  # Special cases in auto mode:
  # 1. New copilot human is deferred to next round (unless they're current speaker)
  # 2. Current speaker enabling copilot: cancel skip job and create run
  #
  # @return [void]
  def recalculate_queue!
    state = load_state
    return start_round! if state.empty?

    old_queue = state["queue"] || []
    spoken = state["spoken"] || []
    round_id = state["round_id"]

    # Get current speaker before recalculating
    old_position = state["position"] || 0
    current_speaker_id = old_queue[old_position]

    # Check if current speaker just enabled copilot
    current_speaker_enabled_copilot = false
    if current_speaker_id && auto_mode_active?
      current_speaker = space.space_memberships.find_by(id: current_speaker_id)
      if current_speaker && !current_speaker.ai_character? && current_speaker.copilot_full?
        # Current speaker is human with copilot - they might have just enabled it
        # Cancel any pending HumanTurn run and schedule their turn as AI
        current_speaker_enabled_copilot = true
        cancel_human_turn_run!(current_speaker_id)
      end
    end

    # Build new queue
    new_queue_ids = build_ordered_queue.map(&:id)

    # When auto mode is active, defer newly added copilot humans to next round
    # Exception: current speaker who just enabled copilot stays in queue
    if auto_mode_active?
      # Find members who are new to the queue (weren't in old_queue)
      new_members = new_queue_ids - old_queue
      # Keep only AI characters from new members; human copilot joins next round
      new_members_to_include = new_members.select do |member_id|
        membership = space.space_memberships.find_by(id: member_id)
        membership&.ai_character?
      end
      # Final queue: old members still eligible + new AI characters
      eligible_ids = (old_queue & new_queue_ids) + new_members_to_include
      # Maintain order from new_queue
      new_queue_ids = new_queue_ids.select { |id| eligible_ids.include?(id) }
    end

    remaining = new_queue_ids - spoken

    if remaining.empty?
      # Everyone has spoken - end round
      handle_round_complete!(state)
      return
    end

    # Find new position
    new_position = if current_speaker_id && remaining.include?(current_speaker_id)
                     remaining.index(current_speaker_id)
    else
                     0 # Start from first remaining speaker
    end

    update_state!(
      queue: remaining,
      position: new_position,
      spoken: spoken,
      round_id: round_id
    )

    broadcast_queue_update
    schedule_current_turn!
  end

  # Stop auto-scheduling without clearing state.
  #
  # This cancels queued runs but preserves the turn queue state so that
  # resuming auto mode can continue from where it left off.
  #
  # Use this when user clicks "Stop" on auto mode.
  #
  # @return [void]
  def stop!
    cancel_existing_queued_runs!
    broadcast_queue_update
  end

  # Clear the queue state completely (full reset).
  #
  # Also cancels any existing queued runs to ensure clean state.
  # Use this for full reset scenarios (e.g., conversation restart).
  #
  # @return [void]
  def clear!
    cancel_existing_queued_runs!
    update_state!({})
    broadcast_queue_update
  end

  # Resume auto-scheduling from current position.
  #
  # If there's an active round with remaining speakers, schedule from current position.
  # If no active round or round is complete, start a new round.
  #
  # @param skip_to_ai [Boolean] if resuming, skip humans without copilot to find first AI
  # @return [void]
  def resume!(skip_to_ai: false)
    # When skip_to_ai is requested, cancel any existing HumanTurn runs
    # This ensures we don't have orphaned HumanTurn runs when auto mode is enabled
    if skip_to_ai
      cancel_human_turn_runs!
    end

    state = load_state

    # If we have an active round with remaining speakers, continue from there
    if state.present? && state["queue"].present?
      queue_ids = state["queue"]
      position = state["position"] || 0
      spoken = state["spoken"] || []
      round_id = state["round_id"]

      # Check if there are remaining speakers in the current round
      if position < queue_ids.length
        # If skip_to_ai is requested, advance past humans without copilot
        if skip_to_ai && auto_mode_active?
          memberships_by_id = space.space_memberships.active.index_by(&:id)

          while position < queue_ids.length
            speaker = memberships_by_id[queue_ids[position]]
            break if speaker&.can_auto_respond? # Found an AI or Copilot user
            spoken << queue_ids[position] # Mark skipped humans as "spoken"
            position += 1
          end

          # Update state with new position
          if position < queue_ids.length
            update_state!(
              queue: queue_ids,
              position: position,
              spoken: spoken,
              round_id: round_id
            )
          end
        end

        # Schedule the current turn (may be AI after skipping)
        if position < queue_ids.length
          schedule_current_turn!
          return
        end
      end
    end

    # No active round or round complete - start a new one
    start_round!(skip_to_ai: skip_to_ai)
  end

  # Recalculate the queue (called when environment changes).
  #
  # This is the public API for external callers (like SpaceMembership callbacks).
  # It delegates to recalculate_queue! which does the actual work.
  #
  # @return [void]
  def recalculate!
    recalculate_queue!
  end

  # Get the turn queue for UI display.
  #
  # @param limit [Integer] max number of speakers to return
  # @return [Array<SpaceMembership>] ordered list of participants
  def turn_queue(limit: 10)
    state = load_state
    return build_ordered_queue.first(limit) if state.empty?

    queue = state["queue"] || []
    position = state["position"] || 0
    remaining_ids = queue[position..]

    # Include :character to avoid N+1 when calling display_name
    memberships_by_id = space.space_memberships.includes(:character).index_by(&:id)
    remaining_ids.first(limit).filter_map { |id| memberships_by_id[id] }
  end

  # Check if auto mode is active.
  #
  # @return [Boolean]
  def auto_mode_active?
    conversation.auto_mode_enabled?
  end

  # Check if any copilot user is active and can respond.
  #
  # @return [Boolean]
  def any_copilot_active?
    space.space_memberships.active.any? { |m| m.copilot_full? && m.can_auto_respond? }
  end

  # Check if auto-scheduling is enabled (auto mode OR copilot active).
  #
  # @return [Boolean]
  def auto_scheduling_enabled?
    auto_mode_active? || any_copilot_active?
  end

  private

  # ============================================================================
  # Run Cleanup
  # ============================================================================

  # Cancel any existing queued runs for this conversation.
  #
  # This prevents unique constraint violations when starting a new round,
  # as the database only allows one queued run per conversation.
  #
  # @return [void]
  def cancel_existing_queued_runs!
    conversation.conversation_runs.queued.find_each do |run|
      # Hide typing indicator if this run has a speaker
      if run.speaker_space_membership_id
        speaker = space.space_memberships.find_by(id: run.speaker_space_membership_id)
        ConversationChannel.broadcast_typing(conversation, membership: speaker, active: false) if speaker
      end

      run.canceled!(
        debug: run.debug.merge(
          "canceled_by" => "scheduler_cleanup",
          "canceled_at" => Time.current.iso8601
        )
      )
    end
  end

  # Cancel any queued HumanTurn runs.
  #
  # Called when auto mode is enabled with skip_to_ai to ensure we don't have
  # orphaned HumanTurn runs blocking the conversation.
  #
  # Uses optimistic locking via status check to handle concurrent updates
  # (e.g., HumanTurnTimeoutJob running at the same time).
  #
  # @return [void]
  def cancel_human_turn_runs!
    conversation.conversation_runs
      .where(type: "ConversationRun::HumanTurn")
      .queued
      .find_each do |run|
        # Use update with WHERE clause for optimistic locking
        # Only update if still queued (handles race with HumanTurnTimeoutJob)
        updated = ConversationRun
          .where(id: run.id, status: "queued")
          .update_all(
            status: "canceled",
            finished_at: Time.current,
            debug: run.debug.merge(
              "canceled_by" => "auto_mode_skip",
              "canceled_at" => Time.current.iso8601
            ).to_json
          )

        Rails.logger.info "[ConversationScheduler] Canceled HumanTurn #{run.id}" if updated > 0
      end
  end

  # ============================================================================
  # State Management
  # ============================================================================

  def load_state
    conversation.turn_queue_state || {}
  end

  def update_state!(state)
    conversation.update_column(:turn_queue_state, state)
    @cached_state = nil
  end

  # ============================================================================
  # Queue Building
  # ============================================================================

  # Build the ordered queue of all participants.
  #
  # Order determined by:
  # 1. Talkativeness factor (descending) - higher speaks first
  # 2. Position (ascending) - tiebreaker
  #
  # @return [Array<SpaceMembership>]
  def build_ordered_queue
    participants = eligible_participants
    participants.sort_by { |m| [-m.talkativeness_factor.to_f, m.position] }
  end

  # Get all participants who should be in the queue.
  #
  # Includes:
  # - AI characters (active, participating)
  # - Human members with copilot_full? enabled
  # - Human members without copilot (if auto mode, they get skip timeout)
  #
  # @return [Array<SpaceMembership>]
  def eligible_participants
    # Include :character to avoid N+1 when calling display_name
    space.space_memberships.participating.includes(:character).to_a
  end

  # ============================================================================
  # Scheduling
  # ============================================================================

  def create_run_for_speaker!(speaker)
    return unless speaker.can_auto_respond?
    return if space.reply_order == "manual"

    # Determine delay
    delay_ms = auto_mode_active? ? space.auto_mode_delay_ms.to_i : 0
    run_after = Time.current + (delay_ms / 1000.0)

    # Determine STI type based on speaker
    run_type = speaker.copilot_full? ? ConversationRun::CopilotTurn : ConversationRun::AutoTurn

    # Use RunPlanner to create the run with appropriate type
    run = Conversations::RunPlanner.create_scheduled_run!(
      conversation: conversation,
      speaker: speaker,
      run_after: run_after,
      reason: speaker.copilot_full? ? "copilot_turn" : "auto_turn",
      run_type: run_type
    )

    # Show typing indicator immediately when run is created
    # This provides instant feedback even if there's a delay before execution
    if run
      ConversationChannel.broadcast_typing(conversation, membership: speaker, active: true)
    end

    run
  end

  def schedule_human_skip!(speaker)
    # Calculate timeout for human turn
    timeout_seconds = (space.auto_mode_delay_ms.to_i / 1000.0) + HUMAN_SKIP_DELAY_SECONDS

    # Get current round_id for validation in timeout job
    state = load_state
    round_id = state["round_id"]

    # Create a HumanTurn run to track state
    ConversationRun::HumanTurn.create_for_human!(
      conversation: conversation,
      speaker: speaker,
      timeout_seconds: timeout_seconds,
      round_id: round_id
    )

    Rails.logger.info "[ConversationScheduler] Created HumanTurn for #{speaker.display_name} with #{timeout_seconds}s timeout (round: #{round_id})"
  end

  def cancel_human_turn_run!(membership_id)
    # Find and cancel any queued HumanTurn run for this speaker
    human_turn = ConversationRun::HumanTurn
      .where(conversation: conversation, speaker_space_membership_id: membership_id)
      .queued
      .first

    if human_turn
      human_turn.canceled!(
        debug: human_turn.debug.merge(
          "canceled_reason" => "speaker_became_auto_respond",
          "canceled_at" => Time.current.iso8601
        )
      )
      Rails.logger.info "[ConversationScheduler] Canceled HumanTurn #{human_turn.id} for membership #{membership_id}"
    end
  rescue StandardError => e
    Rails.logger.warn "[ConversationScheduler] Failed to cancel HumanTurn: #{e.message}"
  end

  # ============================================================================
  # Round Management
  # ============================================================================

  # Check if we should auto-schedule a response (for normal user message → AI response flow).
  #
  # @return [Boolean]
  def should_auto_schedule_response?
    return false if space.reply_order == "manual"

    # Need at least one AI character or copilot user who can respond
    eligible_participants.any?(&:can_auto_respond?)
  end

  # Start a round after a message was created (when no round was active).
  #
  # This builds the queue, marks the speaker as already spoken, and schedules
  # the next speaker. Used for normal conversation flow where user message
  # triggers AI response.
  #
  # @param speaker_membership [SpaceMembership] the speaker who just sent a message
  # @return [void]
  def start_round_after_message!(speaker_membership)
    queue = build_ordered_queue
    return if queue.empty?

    # Increment turns count and decrement speaker resources
    conversation.increment!(:turns_count)
    decrement_speaker_resources!(speaker_membership)

    # Find the speaker's position and calculate next position
    speaker_id = speaker_membership.id
    queue_ids = queue.map(&:id)

    # Mark this speaker as spoken
    spoken = [speaker_id]

    # Find the next speaker (skip the one who just spoke)
    next_position = 0
    queue_ids.each_with_index do |id, idx|
      if id != speaker_id
        next_position = idx
        break
      end
    end

    # If speaker not in queue, start from beginning
    round_id = SecureRandom.uuid
    update_state!(
      queue: queue_ids,
      position: next_position,
      spoken: spoken,
      round_id: round_id
    )

    broadcast_queue_update
    schedule_current_turn!
  end

  def handle_round_complete!(state)
    # Decrement auto mode rounds if active
    if auto_mode_active?
      conversation.decrement_auto_mode_rounds!
    end

    # Check if we should start a new round
    if auto_scheduling_enabled?
      start_round!
    else
      clear!
    end
  end

  def decrement_speaker_resources!(speaker)
    return unless speaker

    if speaker.copilot_full?
      speaker.decrement_copilot_remaining_steps!
    end
  end

  # ============================================================================
  # Broadcasting
  # ============================================================================

  def broadcast_queue_update
    queue_members = turn_queue(limit: 10)

    # Broadcast JSON event for any JS listeners
    queue_data = queue_members.map do |member|
      {
        id: member.id,
        display_name: member.display_name,
        portrait_url: member.respond_to?(:portrait_url) ? member.portrait_url : nil,
      }
    end

    ConversationChannel.broadcast_to(
      conversation,
      type: "conversation_queue_updated",
      conversation_id: conversation.id,
      queue: queue_data
    )

    # Broadcast Turbo Stream to update the queue UI
    return unless space.group?

    Turbo::StreamsChannel.broadcast_replace_to(
      conversation, :messages,
      target: ActionView::RecordIdentifier.dom_id(conversation, :group_queue),
      partial: "messages/group_queue",
      locals: {
        conversation: conversation,
        space: space,
        queue_members: queue_members,
      }
    )
  end
end
