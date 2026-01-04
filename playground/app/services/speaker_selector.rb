# frozen_string_literal: true

# Selects the next speaker for a conversation based on the space's reply_order strategy.
#
# Strategies:
# - manual: No automatic selection; user explicitly picks speaker
# - natural: Mention detection + round-robin rotation
# - list: Strict position-based rotation
# - pooled: Each character speaks at most once per user message epoch
#
class SpeakerSelector
  def initialize(conversation)
    @conversation = conversation
  end

  # Selects a speaker for a user-triggered run.
  #
  # Uses the last assistant speaker as the "previous" speaker so group chats can rotate.
  def select_for_user_turn
    select_next(previous_speaker: conversation.last_assistant_message&.space_membership)
  end

  # Selects a speaker for an auto-mode followup run.
  def select_for_auto_mode(previous_speaker:)
    select_next(previous_speaker: previous_speaker, allow_self: conversation.space.allow_self_responses?)
  end

  def select_manual(speaker_space_membership_id)
    return nil unless speaker_space_membership_id

    membership = conversation.space.space_memberships.active.find_by(id: speaker_space_membership_id)
    return nil unless membership&.can_auto_respond?

    membership
  end

  # Selects an AI character only (excludes copilot users).
  # Used for copilot followup responses where we want the AI character to respond,
  # not another copilot user.
  #
  # Uses round-robin for natural/list strategies to avoid always selecting the first character.
  # For pooled, uses simple random selection (pool semantics don't apply to copilot followup).
  def select_ai_character_only(exclude_participant_id: nil, previous_speaker: nil)
    return nil if conversation.space.reply_order == "manual"

    candidates = ai_character_candidates
    candidates = candidates.reject { |m| m.id == exclude_participant_id } if exclude_participant_id
    return nil if candidates.empty?

    case conversation.space.reply_order
    when "natural", "list"
      # Use round-robin without mention detection (copilot followup context)
      round_robin_select(candidates, previous_speaker, allow_self: true)
    when "pooled"
      # Simple random selection for copilot followup (no pool tracking)
      candidates.sample
    else
      nil
    end
  end

  private

  attr_reader :conversation

  # Gets the last user message for mention detection and pool epoch tracking.
  def last_user_message
    @last_user_message ||= conversation.last_user_message
  end

  def select_next(previous_speaker:, allow_self: true)
    return nil if conversation.space.reply_order == "manual"

    candidates = eligible_candidates
    return nil if candidates.empty?

    case conversation.space.reply_order
    when "natural"
      pick_natural(candidates, previous_speaker, allow_self: allow_self)
    when "list"
      pick_list(candidates, previous_speaker, allow_self: allow_self)
    when "pooled"
      pick_pooled(candidates, previous_speaker, allow_self: allow_self)
    else
      nil
    end
  end

  def eligible_candidates
    conversation.ai_respondable_participants.by_position.to_a.select(&:can_auto_respond?)
  end

  # Returns only pure AI characters (character_id present, user_id nil).
  # Excludes copilot users which have both user_id and character_id.
  def ai_character_candidates
    conversation.space.space_memberships.participating.ai_characters.by_position.to_a.select(&:can_auto_respond?)
  end

  # Natural strategy: mention detection first, then round-robin rotation.
  #
  # 1. If the last user message mentions a candidate's display_name (case-insensitive),
  #    select that candidate. If multiple are mentioned, select the first by position.
  # 2. Otherwise, use round-robin starting from the position after previous_speaker.
  def pick_natural(candidates, previous_speaker, allow_self:)
    # 1. Mention detection
    if (mentioned = detect_mentioned_candidate(candidates))
      return mentioned
    end

    # 2. Round-robin
    round_robin_select(candidates, previous_speaker, allow_self: allow_self)
  end

  # Detects if any candidate is mentioned in the last user message.
  #
  # @param candidates [Array<SpaceMembership>] candidates to check
  # @return [SpaceMembership, nil] first mentioned candidate by position, or nil
  def detect_mentioned_candidate(candidates)
    content = last_user_message&.content
    return nil if content.blank?

    content_lower = content.downcase
    candidates.find { |c| content_lower.include?(c.display_name.downcase) }
  end

  # Round-robin selection starting from the position after previous_speaker.
  #
  # @param candidates [Array<SpaceMembership>] candidates sorted by position
  # @param previous_speaker [SpaceMembership, nil] the previous speaker
  # @param allow_self [Boolean] whether the previous speaker can be selected again
  # @return [SpaceMembership, nil]
  def round_robin_select(candidates, previous_speaker, allow_self:)
    return candidates.first unless previous_speaker

    idx = candidates.index { |m| m.id == previous_speaker.id }
    # If previous_speaker is not in candidates, start from first
    return candidates.first unless idx

    # Try each position starting from idx+1
    candidates.size.times do |offset|
      next_idx = (idx + 1 + offset) % candidates.size
      candidate = candidates[next_idx]
      next if !allow_self && candidate.id == previous_speaker.id
      return candidate
    end

    nil
  end

  # List strategy: strict position-based rotation.
  def pick_list(candidates, previous_speaker, allow_self:)
    return candidates.first unless previous_speaker

    idx = candidates.index { |m| m.id == previous_speaker.id } || -1
    next_speaker = candidates[(idx + 1) % candidates.size]
    return next_speaker if allow_self || previous_speaker.nil? || next_speaker.id != previous_speaker.id

    nil
  end

  # Pooled strategy: each candidate speaks at most once per user message epoch.
  def pick_pooled(candidates, previous_speaker, allow_self:)
    spoken_ids = spoken_participant_ids_for_current_epoch

    # Filter out candidates who have already spoken in this epoch
    available = candidates.reject { |m| spoken_ids.include?(m.id) }

    # Also apply allow_self constraint
    available = available.reject { |m| m.id == previous_speaker&.id } unless allow_self

    # Pool exhausted
    return nil if available.empty?

    available.sample
  end

  def spoken_participant_ids_for_current_epoch
    epoch_message = last_user_message
    return [] unless epoch_message

    conversation
      .messages
      .where(role: "assistant")
      .after_cursor(epoch_message)
      .distinct
      .pluck(:space_membership_id)
  end
end
