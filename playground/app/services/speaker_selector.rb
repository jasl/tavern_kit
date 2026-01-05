# frozen_string_literal: true

# Selects the next speaker for a conversation based on the space's reply_order strategy.
#
# Strategies:
# - manual: No automatic selection; user explicitly picks speaker
# - natural: Mention detection (whole-word) + talkativeness probability + round-robin fallback
# - list: Strict position-based rotation
# - pooled: Each character speaks at most once per user message epoch
#
# Natural order follows SillyTavern's activateNaturalOrder logic:
# 1. Extract mentions from last message (user or assistant) using whole-word matching
# 2. Activate candidates by talkativeness probability roll (talkativeness >= random())
# 3. If any candidates activated, randomly select one
# 4. Fallback to chatty members (talkativeness > 0), then round-robin
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

  # Gets the last user message for pool epoch tracking.
  # @return [Message, nil]
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

  # Natural strategy: SillyTavern-compatible speaker selection.
  #
  # 1. Get activation text from last message (user or assistant)
  # 2. Find mentioned candidates using whole-word matching
  # 3. Activate candidates by talkativeness probability roll
  # 4. If any candidates activated (mentioned or by talkativeness), randomly select one
  # 5. Fallback to chatty members (talkativeness > 0), then round-robin
  #
  # @param candidates [Array<SpaceMembership>] eligible candidates sorted by position
  # @param previous_speaker [SpaceMembership, nil] the previous speaker
  # @param allow_self [Boolean] whether the previous speaker can be selected again
  # @return [SpaceMembership, nil]
  def pick_natural(candidates, previous_speaker, allow_self:)
    # Determine banned speaker (for !allow_self_responses)
    banned_speaker_id = allow_self ? nil : previous_speaker&.id

    # Get activation text from last message (user or assistant)
    activation_text = last_activation_message&.content

    # 1. Find mentioned candidates (whole-word matching)
    mentioned = detect_mentioned_candidates(candidates, activation_text, banned_speaker_id)

    # 2. Activate by talkativeness probability
    activated_by_talkativeness = activate_by_talkativeness(candidates, banned_speaker_id)

    # 3. Combine mentioned + talkativeness-activated (deduplicate)
    all_activated = (mentioned + activated_by_talkativeness).uniq(&:id)

    # 4. If any activated, randomly select one
    return all_activated.sample if all_activated.any?

    # 5. Fallback: try chatty members (talkativeness > 0)
    chatty = candidates.reject { |c| c.id == banned_speaker_id }
                       .select { |c| c.talkativeness_factor.to_f > 0 }
    return chatty.sample if chatty.any?

    # 6. Final fallback: round-robin
    round_robin_select(candidates, previous_speaker, allow_self: allow_self)
  end

  # Gets the last message (user or assistant) for activation text extraction.
  # This matches SillyTavern's behavior where mentions can be detected from
  # the last assistant message as well (for auto-mode followups).
  #
  # @return [Message, nil]
  def last_activation_message
    @last_activation_message ||= conversation.messages
                                             .where(role: %w[user assistant])
                                             .order(:seq, :id)
                                             .last
  end

  # Extracts all words from text using whole-word boundary matching.
  # Matches SillyTavern's extractAllWords function using /\b\w+\b/ regex.
  #
  # @param text [String, nil] text to extract words from
  # @return [Array<String>] lowercase words
  def extract_words(text)
    return [] if text.blank?

    text.scan(/\b\w+\b/i).map(&:downcase).uniq
  end

  # Detects candidates mentioned in the activation text using whole-word matching.
  # A candidate is mentioned if any word from their display_name appears in the text.
  # For example, "Misaka Mikoto" is mentioned if either "misaka" or "mikoto" appears.
  #
  # @param candidates [Array<SpaceMembership>] candidates to check
  # @param text [String, nil] text to search for mentions
  # @param banned_speaker_id [Integer, nil] speaker ID to exclude
  # @return [Array<SpaceMembership>] mentioned candidates
  def detect_mentioned_candidates(candidates, text, banned_speaker_id)
    return [] if text.blank?

    input_words = extract_words(text)
    return [] if input_words.empty?

    candidates.select do |candidate|
      next false if candidate.id == banned_speaker_id

      name_words = extract_words(candidate.display_name)
      (name_words & input_words).any?
    end
  end

  # Activates candidates by rolling against their talkativeness factor.
  # Each candidate with talkativeness >= random() is activated.
  # Matches SillyTavern's talkativeness probability check.
  #
  # @param candidates [Array<SpaceMembership>] candidates to check
  # @param banned_speaker_id [Integer, nil] speaker ID to exclude
  # @return [Array<SpaceMembership>] activated candidates
  def activate_by_talkativeness(candidates, banned_speaker_id)
    candidates.select do |candidate|
      next false if candidate.id == banned_speaker_id

      talkativeness = candidate.talkativeness_factor.to_f
      talkativeness = SpaceMembership::DEFAULT_TALKATIVENESS_FACTOR if talkativeness.zero? && candidate.talkativeness_factor.nil?
      roll_value = rand
      talkativeness >= roll_value
    end
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
