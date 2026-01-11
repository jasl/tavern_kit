# frozen_string_literal: true

# Controller for conversation timelines.
class ConversationsController < Conversations::ApplicationController
  include Authorization
  include TrackedSpaceVisit

  layout "conversation", only: :show

  skip_before_action :set_conversation, only: %i[index create]
  before_action :set_space, only: %i[create]
  before_action :ensure_space_writable, only: %i[update regenerate generate branch stop toggle_auto_mode cancel_stuck_run retry_stuck_run]
  before_action :remember_last_space_visited, only: :show

  # GET /conversations
  # Lists all root conversations for the current user, sorted by recent activity.
  def index
    # Get all root conversations the user has access to
    conversations = Conversation.root
                                .joins(:space)
                                .where(spaces: { type: "Spaces::Playground" })
                                .merge(Space.accessible_to(Current.user))
                                .merge(Space.active)
                                .with_last_message_preview.by_recent_activity
                                .includes(space: { characters: { portrait_attachment: :blob } })
    set_page_and_extract_portion_from conversations, per_page: 15

    @archived_conversations = Conversation.root
                                          .joins(:space)
                                          .where(spaces: { type: "Spaces::Playground" })
                                          .merge(Space.accessible_to(Current.user))
                                          .merge(Space.archived)
                                          .includes(:space)
                                          .order("spaces.name ASC")
  end

  # POST /playgrounds/:playground_id/conversations
  # Creates a root conversation in a playground.
  def create
    conversation = @space.conversations.create!(
      title: conversation_params[:title].presence || "Conversation",
      kind: "root"
    )

    conversation.create_first_messages!

    redirect_to conversation_url(conversation)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to playground_url(@space), alert: e.record.errors.full_messages.to_sentence
  end

  # GET /conversations/:id
  def show
    @messages = @conversation.messages.recent_chronological(50).with_space_membership.includes(conversation_run: :speaker_space_membership)
    @message = @conversation.messages.new
    @current_membership = @space_membership
    @has_more = @messages.any? && @conversation.messages.where("seq < ?", @messages.first.seq).exists?

    # Preload tree data for branch navigation
    @tree_conversations = @conversation.tree_conversations
      .includes(:forked_from_message, :parent_conversation)
      .chronological
  end

  # PATCH /conversations/:id
  # Updates conversation attributes (title, authors_note, etc.)
  def update
    @conversation.update!(conversation_params)

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to conversation_url(@conversation) }
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.turbo_stream { head :unprocessable_entity }
      format.html { redirect_to conversation_url(@conversation), alert: e.record.errors.full_messages.to_sentence }
    end
  end

  # POST /conversations/:id/regenerate
  # Triggers regeneration of an assistant message.
  #
  # Behavior:
  # - Without message_id: regenerates the tail message only if it's an assistant message
  # - With message_id: regenerates the specified assistant message
  #
  # Any regeneration of a non-tail message will auto-branch to preserve timeline consistency
  # (per SillyTavern Timelines behavior).
  def regenerate
    # Get the absolute tail message (max seq)
    tail_message = @conversation.messages.order(seq: :desc).first

    target_message = if params[:message_id].present?
      @conversation.messages.find(params[:message_id])
    else
      # No message_id: only allow regenerate if tail is assistant
      tail_message if tail_message&.assistant?
    end

    # Case 1: No message to regenerate (tail is not assistant when no message_id provided)
    unless target_message
      return respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html do
          redirect_to conversation_url(@conversation),
                      alert: t("messages.last_message_not_assistant", default: "Last message is not assistant.")
        end
      end
    end

    # Case 2: Target is not an assistant message (when message_id is explicitly provided)
    unless target_message.assistant?
      return respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html do
          redirect_to conversation_url(@conversation),
                      alert: t("messages.cannot_regenerate_non_assistant", default: "Cannot regenerate non-assistant message.")
        end
      end
    end

    # Case 3: Target is not the tail message -> auto-branch to preserve timeline consistency
    if target_message.id != tail_message&.id
      return handle_non_tail_regenerate(target_message)
    end

    # Case 4: Target == tail AND is assistant
    # Check if we should use last_turn mode (delete all AI messages in the turn, re-queue generation)
    if @space.group? && @space.group_regenerate_mode_last_turn?
      return handle_last_turn_regenerate
    end

    # Default: in-place swipe (single message regeneration)
    Conversations::RunPlanner.plan_regenerate!(conversation: @conversation, target_message: target_message)

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to conversation_url(@conversation, anchor: helpers.dom_id(target_message)) }
    end
  end

  # POST /conversations/:id/branch
  # Creates a branch (fork) from a specific message.
  #
  # Parameters (via request body):
  #   message_id: ID of the message to fork from (required)
  #   title: Title for the new branch (optional, defaults to "Branch")
  #   visibility: "shared" or "private" (optional, defaults to "shared")
  #
  # For short conversations, creates branch synchronously and redirects.
  # For long conversations (50+ messages), creates branch asynchronously
  # and shows a toast notification. User will be notified when complete.
  def branch
    message = @conversation.messages.find_by(id: branch_params[:message_id])
    return head :not_found unless message

    result = Conversations::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: message,
      kind: "branch",
      title: branch_params[:title],
      visibility: branch_params[:visibility]
    ).call

    if result.success?
      if result.async?
        # Async mode: stay on current page, show toast
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.action(
              :show_toast,
              nil,
              partial: "shared/toast",
              locals: {
                message: t("conversations.fork.creating", title: result.conversation.title),
                type: :info,
              }
            )
          end
          format.html do
            redirect_to conversation_url(@conversation),
                        notice: t("conversations.fork.creating", title: result.conversation.title)
          end
        end
      else
        # Sync mode: redirect to new branch
        redirect_to conversation_url(result.conversation)
      end
    else
      redirect_to conversation_url(@conversation), alert: result.error
    end
  end

  # POST /conversations/:id/generate
  # Triggers an AI response without requiring a user message.
  #
  # Parameters:
  #   speaker_id: (optional) SpaceMembership ID to force a specific speaker
  #
  # Behavior:
  # - With speaker_id: Uses plan_force_talk! (works even for muted members)
  # - Without speaker_id + manual mode: Randomly selects an active AI character
  # - Without speaker_id + non-manual: Uses TurnScheduler to select speaker
  def generate
    speaker = if params[:speaker_id].present?
      # Force talk mode: allow any active AI character (including muted)
      @space.space_memberships.active.ai_characters.find_by(id: params[:speaker_id])
    elsif @space.manual?
      # Manual mode: random selection from active participating AI characters
      @space.space_memberships.participating.ai_characters.sample
    else
      # Non-manual mode: use normal speaker selection
      TurnScheduler::Queries::NextSpeaker.call(conversation: @conversation)
    end

    unless speaker
      return respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to conversation_url(@conversation), alert: t("messages.no_speaker_available", default: "No AI character available to respond.") }
      end
    end

    Conversations::RunPlanner.plan_force_talk!(
      conversation: @conversation,
      speaker_space_membership_id: speaker.id
    )

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to conversation_url(@conversation) }
    end
  end

  # POST /conversations/:id/stop
  # Requests cancellation of any running generation for this conversation.
  #
  # Behavior:
  # - Sets cancel_requested_at on running run (idempotent via request_cancel!)
  # - Immediately broadcasts stream_complete + typing_stop to clear UI
  # - Returns 204 regardless of whether a run existed
  def stop
    running_run = @conversation.conversation_runs.running.first

    if running_run
      running_run.request_cancel!

      # Immediately broadcast to clear typing indicator (don't wait for executor)
      if running_run.speaker_space_membership_id
        ConversationChannel.broadcast_stream_complete(@conversation, space_membership_id: running_run.speaker_space_membership_id)
        membership = @space.space_memberships.find_by(id: running_run.speaker_space_membership_id)
        ConversationChannel.broadcast_typing(@conversation, membership: membership, active: false) if membership
      end
    end

    head :no_content
  end

  # POST /conversations/:id/toggle_auto_mode
  # Toggles auto-mode for AI-to-AI conversation in group chats.
  #
  # Parameters:
  #   rounds: Number of rounds to enable (1-10), or 0 to disable
  #
  # Auto-mode allows AI characters to take turns automatically without
  # requiring user intervention. Rounds are decremented after each AI response.
  # When rounds reach 0, auto-mode is automatically disabled.
  #
  # Only available for group chats (multiple AI characters).
  def toggle_auto_mode
    # Only allow auto-mode for group chats
    unless @space.group?
      return respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to conversation_url(@conversation), alert: t("conversations.auto_mode.group_only", default: "Auto-mode is only available for group chats.") }
      end
    end

    rounds = params[:rounds].to_i.clamp(0, Conversation::MAX_AUTO_MODE_ROUNDS)

    if rounds > 0
      # Auto mode and Copilot are mutually exclusive - disable all Copilot modes
      disable_all_copilot_modes!
      # Force reload memberships to ensure Turbo Stream renders see the updated copilot state
      @space.space_memberships.reload

      @conversation.start_auto_mode!(rounds: rounds)
      # Start a new round - skip_to_ai: true makes AI respond immediately without waiting for human
      TurnScheduler.start_round!(@conversation, skip_to_ai: true)
    else
      @conversation.stop_auto_mode!
      # Stop scheduling
      TurnScheduler.stop!(@conversation)
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to conversation_url(@conversation) }
    end
  end

  # GET /conversations/:id/export
  # Exports conversation in JSONL (re-importable) or TXT (readable) format.
  #
  # Parameters:
  #   format: :jsonl or :txt (defaults to :jsonl)
  #
  # JSONL format includes:
  # - Metadata header (conversation info, space settings)
  # - Messages with all swipes (one message per line)
  #
  # TXT format includes:
  # - Readable transcript with timestamps and speaker names
  def export
    format_type = params[:format]&.to_sym || :jsonl

    case format_type
    when :jsonl
      export_data = Conversations::Exporter.to_jsonl(@conversation)
      filename = "#{safe_filename(@conversation)}.jsonl"
      send_data export_data, filename: filename, type: "application/jsonl"
    when :txt
      export_data = Conversations::Exporter.to_txt(@conversation)
      filename = "#{safe_filename(@conversation)}.txt"
      send_data export_data, filename: filename, type: "text/plain"
    else
      head :bad_request
    end
  end

  # POST /conversations/:id/cancel_stuck_run
  # Cancels any active (queued or running) run for manual recovery.
  #
  # Useful when a run gets stuck due to:
  # - Worker process crash
  # - LLM provider hang
  # - Network issues
  #
  # Behavior:
  # - Finds first active run (queued or running)
  # - Marks it as canceled with debug info
  # - Clears the turn queue state
  # - Broadcasts UI updates
  def cancel_stuck_run
    active_run = @conversation.conversation_runs.active.first

    unless active_run
      return respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.action(
            :show_toast,
            nil,
            partial: "shared/toast",
            locals: {
              message: t("conversations.no_active_run", default: "No active run to cancel."),
              type: :info,
            }
          )
        end
        format.html { redirect_to conversation_url(@conversation), notice: t("conversations.no_active_run", default: "No active run to cancel.") }
      end
    end

    # Cancel the run
    active_run.canceled!(
      debug: active_run.debug.merge(
        "canceled_by" => "user_manual",
        "canceled_reason" => "stuck_run_recovery",
        "canceled_at" => Time.current.iso8601,
        "canceled_by_user_id" => Current.user.id
      )
    )

    # Clear turn queue state and broadcast updates
    TurnScheduler.stop!(@conversation)

    # Clear typing indicator if speaker exists
    if active_run.speaker_space_membership_id
      membership = @space.space_memberships.find_by(id: active_run.speaker_space_membership_id)
      if membership
        ConversationChannel.broadcast_stream_complete(@conversation, space_membership_id: membership.id)
        ConversationChannel.broadcast_typing(@conversation, membership: membership, active: false)
      end
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.action(
          :show_toast,
          nil,
          partial: "shared/toast",
          locals: {
            message: t("conversations.run_canceled", default: "Run canceled successfully. You can continue the conversation."),
            type: :success,
          }
        )
      end
      format.html { redirect_to conversation_url(@conversation), notice: t("conversations.run_canceled", default: "Run canceled successfully.") }
    end
  end

  def retry_stuck_run
    # Try to find an active run (stuck in queued/running)
    active_run = @conversation.conversation_runs.active.first

    # If no active run, check if the last run failed and can be retried
    if active_run.nil?
      last_run = @conversation.conversation_runs.order(created_at: :desc).first
      if last_run&.failed? && last_run.speaker_space_membership_id.present?
        return retry_failed_run(last_run)
      end

      return respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.action(
            :show_toast,
            nil,
            partial: "shared/toast",
            locals: {
              message: t("conversations.no_run_to_retry", default: "No run to retry."),
              type: :info,
            }
          )
        end
        format.html { redirect_to conversation_url(@conversation), notice: t("conversations.no_run_to_retry", default: "No run to retry.") }
      end
    end

    # Force re-kick the active run
    Conversations::RunPlanner.kick!(active_run, force: true)

    # Show typing indicator
    if active_run.speaker_space_membership_id
      membership = @space.space_memberships.find_by(id: active_run.speaker_space_membership_id)
      ConversationChannel.broadcast_typing(@conversation, membership: membership, active: true) if membership
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.action(
          :show_toast,
          nil,
          partial: "shared/toast",
          locals: {
            message: t("conversations.run_retried", default: "Retrying AI response..."),
            type: :info,
          }
        )
      end
      format.html { redirect_to conversation_url(@conversation), notice: t("conversations.run_retried", default: "Retrying AI response...") }
    end
  end

  # Retry a failed run by creating a new run for the same speaker
  def retry_failed_run(failed_run)
    if failed_run.regenerate?
      target_message_id = failed_run.debug&.dig("target_message_id") || failed_run.debug&.dig("trigger_message_id")
      target_message = target_message_id ? @conversation.messages.find_by(id: target_message_id) : nil

      # Regenerate runs require a target message - if it's been deleted, we can't retry
      unless target_message
        return respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.action(
              :show_toast,
              nil,
              partial: "shared/toast",
              locals: {
                message: t("conversations.regenerate_target_deleted", default: "Cannot retry: the message to regenerate has been deleted."),
                type: :error,
              }
            )
          end
          format.html { redirect_to conversation_url(@conversation), alert: t("conversations.regenerate_target_deleted", default: "Cannot retry: the message to regenerate has been deleted.") }
        end
      end

      run = Conversations::RunPlanner.plan_regenerate!(conversation: @conversation, target_message: target_message)
      return respond_retry_failed_run(run: run, speaker_id: failed_run.speaker_space_membership_id)
    end

    speaker = @space.space_memberships.find_by(id: failed_run.speaker_space_membership_id)

    unless speaker&.can_auto_respond?
      return respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.action(
            :show_toast,
            nil,
            partial: "shared/toast",
            locals: {
              message: t("conversations.cannot_retry_run", default: "Cannot retry this run."),
              type: :error,
            }
          )
        end
        format.html { redirect_to conversation_url(@conversation), alert: t("conversations.cannot_retry_run", default: "Cannot retry this run.") }
      end
    end

    # Create a new run for the same speaker
    run = Conversations::RunPlanner.create_scheduled_run!(
      conversation: @conversation,
      speaker: speaker,
      run_after: Time.current,
      reason: "retry_failed",
      kind: failed_run.kind # Use the same run kind
    )

    respond_retry_failed_run(run: run, speaker: speaker)
  end

  # GET /conversations/:id/health
  # Returns conversation health status for frontend polling.
  #
  # Used for periodic health checks to detect:
  # - Stuck runs (running too long without progress)
  # - Failed runs that need attention
  # - Missing runs (should have a run but doesn't)
  #
  # Response JSON:
  #   status: "healthy" | "stuck" | "failed" | "idle_unexpected"
  #   message: Human-readable description
  #   action: "none" | "retry" | "generate"
  #   details: { run_id, speaker_name, duration_seconds, etc. }
  def health
    health_status = Conversations::HealthChecker.check(@conversation)

    respond_to do |format|
      format.json { render json: health_status }
    end
  end

  private

  def respond_retry_failed_run(run:, speaker: nil, speaker_id: nil)
    speaker ||= @space.space_memberships.find_by(id: speaker_id)

    if run && speaker
      ConversationChannel.broadcast_typing(@conversation, membership: speaker, active: true)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.action(
            :show_toast,
            nil,
            partial: "shared/toast",
            locals: {
              message: t("conversations.run_retried", default: "Retrying AI response..."),
              type: :info,
            }
          )
        end
        format.html { redirect_to conversation_url(@conversation), notice: t("conversations.run_retried", default: "Retrying AI response...") }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.action(
            :show_toast,
            nil,
            partial: "shared/toast",
            locals: {
              message: t("conversations.retry_failed", default: "Failed to retry. Please try again."),
              type: :error,
            }
          )
        end
        format.html { redirect_to conversation_url(@conversation), alert: t("conversations.retry_failed", default: "Failed to retry. Please try again.") }
      end
    end
  end

  # Disable all Copilot modes for human members in the space.
  # Called when enabling Auto mode to ensure mutual exclusivity.
  def disable_all_copilot_modes!
    @space.space_memberships.where(kind: "human").where.not(copilot_mode: "none").find_each do |membership|
      membership.update!(copilot_mode: "none", copilot_remaining_steps: 0)
      # Broadcast copilot_disabled event via ActionCable so the frontend updates
      # This is critical for handling race conditions when user clicks Copilot then Auto mode
      Message::Broadcasts.broadcast_copilot_disabled(membership, reason: "auto_mode_enabled")
    end
  end

  def safe_filename(conversation)
    base_name = conversation.title.presence || "conversation_#{conversation.id}"
    timestamp = conversation.updated_at.strftime("%Y%m%d_%H%M%S")
    sanitized = base_name.gsub(/[^a-zA-Z0-9_\-\s]/, "").gsub(/\s+/, "_").truncate(50, omission: "")
    "#{sanitized}_#{timestamp}"
  end

  def set_space
    @space = Current.user.spaces.playgrounds.merge(Space.accessible_to(Current.user)).find_by(id: params[:playground_id])
    return if @space

    redirect_to root_url, alert: t("playgrounds.not_found", default: "Playground not found")
  end

  def conversation_params
    params.fetch(:conversation, {}).permit(
      :title,
      :authors_note,
      :authors_note_position,
      :authors_note_depth,
      :authors_note_role
    )
  end

  def branch_params
    params.permit(:message_id, :title, :visibility)
  end

  # Auto-branch when regenerating a non-tail assistant message.
  # Any non-tail regenerate will auto-branch to preserve timeline consistency.
  # Creates a branch from the target message, then regenerates the cloned message in the branch.
  # This preserves the original conversation timeline.
  #
  # Note: Forces sync mode because we need to regenerate immediately after fork.
  def handle_non_tail_regenerate(target_message)
    result = Conversations::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: target_message,
      kind: "branch",
      async: false # Force sync to ensure messages are ready for regeneration
    ).call

    unless result.success?
      return redirect_to conversation_url(@conversation), alert: result.error
    end

    # Find the cloned target message in the new branch and regenerate it
    cloned_message = result.conversation.messages.find_by(origin_message_id: target_message.id)
    Conversations::RunPlanner.plan_regenerate!(conversation: result.conversation, target_message: cloned_message)

    redirect_to conversation_url(result.conversation)
  end

  # Handle last_turn regeneration mode for group chats.
  # Delegates to Conversations::LastTurnRegenerator service for robust handling of:
  # - Atomic message deletion (no partial deletes)
  # - Fork point protection (auto-branches when needed)
  # - Concurrent fork handling (rescues InvalidForeignKey)
  #
  # This mimics SillyTavern's group chat regeneration behavior.
  def handle_last_turn_regenerate
    result = Conversations::LastTurnRegenerator.new(
      conversation: @conversation,
      on_messages_deleted: ->(ids, conv) {
        ids.each { |id| Turbo::StreamsChannel.broadcast_remove_to(conv, :messages, target: "message_#{id}") }
        Message::Broadcasts.broadcast_group_queue_update(conv)
      }
    ).call

    case result.outcome
    when :success
      # Messages deleted successfully, queue generation
      Conversations::RunPlanner.plan_user_turn!(
        conversation: @conversation,
        trigger: "regenerate_turn"
      )

      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html { redirect_to conversation_url(@conversation) }
      end

    when :fallback_branch
      # Fork point detected (upfront or concurrent), created a branch
      Conversations::RunPlanner.plan_user_turn!(
        conversation: result.conversation,
        trigger: "regenerate_turn"
      )

      redirect_to conversation_url(result.conversation)

    when :nothing_to_regenerate
      # No user messages exist - nothing to regenerate
      # This preserves greeting messages and provides clear feedback.
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: render_to_string(
            partial: "shared/toast_turbo_stream",
            locals: {
              message: t("conversations.nothing_to_regenerate",
                         default: "Nothing to regenerate yet. Send a message first."),
              type: "warning",
              duration: 5000,
            }
          ), status: :unprocessable_entity
        end
        format.html do
          redirect_to conversation_url(@conversation),
                      alert: t("conversations.nothing_to_regenerate",
                               default: "Nothing to regenerate yet. Send a message first.")
        end
      end

    when :error
      # Unexpected error (e.g., branch creation failed)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: render_to_string(
            partial: "shared/toast_turbo_stream",
            locals: { message: result.error, type: "error", duration: 5000 }
          ), status: :unprocessable_entity
        end
        format.html { redirect_to conversation_url(@conversation), alert: result.error }
      end
    end
  end
end
