import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { setCableConnected } from "../conversation_state"
import { subscribeToChannel, unsubscribe } from "../chat/cable_subscription"
import { CABLE_CONNECTED_EVENT, CABLE_DISCONNECTED_EVENT, dispatchWindowEvent } from "../chat/events"
import { setupMessagesObserver, disconnectMessagesObserver } from "../chat/conversation_channel/messages_observer"
import { setupDuplicateMessagePrevention, teardownDuplicateMessagePrevention } from "../chat/conversation_channel/duplicate_message_prevention"
import { handleQueueUpdated as handleQueueUpdatedEvent } from "../chat/conversation_channel/queue_updates"
import { showTypingIndicator, hideTypingIndicator, updateTypingContent, handleStreamComplete, startStuckDetection, clearStuckTimeout, showStuckWarning, hideStuckWarning, resetTypingTimeout, clearTypingTimeout, scrollToTypingIndicator } from "../chat/conversation_channel/typing_indicator"
import { confirmCancelStuckRun, cancelStuckRun, retryStuckRun } from "../chat/conversation_channel/stuck_run_actions"
import { showRunErrorAlert, hideRunErrorAlert, retryFailedRun } from "../chat/conversation_channel/run_error_alert"
import { handleRunSkipped, handleRunCanceled, handleRunFailed, getSkippedReasonMessage } from "../chat/conversation_channel/run_toasts"
import { startHealthCheck, stopHealthCheck, performHealthCheck, handleHealthStatus } from "../chat/conversation_channel/health_check"
import { showIdleAlert, hideIdleAlert, generateFromIdleAlert } from "../chat/conversation_channel/idle_alert"
import { showToast } from "../request_helpers"

/**
 * Conversation Channel Controller
 *
 * Unified controller for conversation-level JSON events from ConversationChannel:
 * - typing_start: Show typing indicator with correct styling
 * - typing_stop: Hide typing indicator
 * - stream_chunk: Update typing indicator with streaming content
 * - stream_complete: Signal generation is complete
 * - run_skipped: Show warning toast when a run was skipped (e.g., due to state change)
 * - run_canceled: Show info toast when a run was canceled by the user
 * - run_failed: Show error toast when a run failed with an error
 *
 * All DOM updates for messages go through Turbo Streams separately.
 * This controller only handles the typing indicator and streaming preview.
 *
 * ## Stuck Run Detection
 *
 * If the typing indicator is visible for more than `stuckThresholdValue` milliseconds
 * without receiving a stream chunk, a warning is shown with a "Cancel" button.
 * This helps users recover from stuck runs.
 */
export default class extends Controller {
  static targets = [
    "typingIndicator", "typingName", "typingContent", "typingAvatarImg", "typingBubble",
    "stuckWarning",
    "runErrorAlert", "runErrorMessage", // Error alert that blocks progress
    "idleAlert", "idleAlertMessage", "idleAlertSpeaker" // Alert for unexpected idle state
  ]
  static values = {
    conversation: Number,
    cancelUrl: String, // URL for cancel_stuck_run action
    retryUrl: String, // URL for retry_stuck_run action
    healthUrl: String, // URL for health check
    generateUrl: String, // URL to trigger new generation
    timeout: { type: Number, default: 60000 }, // Auto-hide after 60s (failsafe)
    stuckThreshold: { type: Number, default: 30000 }, // Show stuck warning after 30s
    healthCheckInterval: { type: Number, default: 30000 } // Health check every 30s
  }

  connect() {
    // Ensure indicators start hidden even if the page is restored from Turbo cache
    this.hideTypingIndicator()
    this.hideStuckWarning()
    this.hideRunErrorAlert()
    this.hideIdleAlert()

    this.manualDisconnect = false
    this.cableConnected = null
    this.hasEverConnected = false

    this.subscribeToChannel()
    this.timeoutId = null
    this.stuckTimeoutId = null
    this.healthCheckIntervalId = null
    this.lastChunkAt = null
    this.currentSpaceMembershipId = null
    this.failedRunId = null
    this.lastHealthStatus = null
    this.lastQueueRevision = null

    // Failsafe: if we miss stream_complete/typing_stop (e.g., during cable reconnect),
    // hide the typing indicator as soon as a new message is appended to the list.
    setupMessagesObserver(this)

    // Prevent duplicate message appends.
    // User messages are delivered twice: via HTTP response (reliable for sender)
    // and via ActionCable broadcast (for other users). This handler prevents
    // the sender from seeing duplicates.
    setupDuplicateMessagePrevention(this)

    // Start periodic health check
    this.startHealthCheck()
  }

  disconnect() {
    this.manualDisconnect = true
    this.unsubscribeFromChannel()
    this.clearTimeout()
    this.clearStuckTimeout()
    this.stopHealthCheck()
    disconnectMessagesObserver(this)
    teardownDuplicateMessagePrevention(this)
  }

  /**
   * Subscribe to ConversationChannel for all JSON events.
   */
  async subscribeToChannel() {
    const conversationId = this.conversationValue
    if (!conversationId) return

    this.manualDisconnect = false
    this.channel = await subscribeToChannel(
      { channel: "ConversationChannel", conversation_id: conversationId },
      {
        received: this.handleMessage.bind(this),
        connected: this.handleChannelConnected.bind(this),
        disconnected: this.handleChannelDisconnected.bind(this),
        rejected: this.handleChannelRejected.bind(this)
      },
      { label: "ConversationChannel" }
    )
  }

  unsubscribeFromChannel() {
    unsubscribe(this.channel)
    this.channel = null
  }

  handleChannelConnected() {
    const wasDisconnected = this.cableConnected === false
    const reconnected = this.hasEverConnected && wasDisconnected

    this.cableConnected = true
    this.hasEverConnected = true
    setCableConnected(this.conversationValue, true)

    dispatchWindowEvent(CABLE_CONNECTED_EVENT, { conversationId: this.conversationValue, reconnected })

    if (reconnected) {
      showToast("Reconnected.", "info", 1500)
      // Trigger an immediate health check to resync UI state after missed events.
      setTimeout(() => this.performHealthCheck(), 250)
    }
  }

  handleChannelDisconnected() {
    if (this.manualDisconnect) return
    if (this.cableConnected === false) return

    this.cableConnected = false
    setCableConnected(this.conversationValue, false)

    dispatchWindowEvent(CABLE_DISCONNECTED_EVENT, { conversationId: this.conversationValue })

    showToast("Connection lost. Reconnecting…", "warning", 3000)
  }

  handleChannelRejected() {
    if (this.manualDisconnect) return

    this.cableConnected = false
    setCableConnected(this.conversationValue, false)
    logger.warn("ConversationChannel subscription rejected")
  }

  /**
   * Handle incoming ActionCable messages.
   */
  handleMessage(data) {
    if (!data || !data.type) return

    switch (data.type) {
      case "typing_start":
        showTypingIndicator(this, data)
        break
      case "typing_stop":
        hideTypingIndicator(this, data.space_membership_id)
        break
      case "stream_chunk":
        updateTypingContent(this, data.content, data.space_membership_id)
        break
      case "stream_complete":
        handleStreamComplete(this, data.space_membership_id)
        break
      case "run_skipped":
        handleRunSkipped(data.reason, data.message)
        break
      case "run_canceled":
        handleRunCanceled()
        break
      case "run_failed":
        handleRunFailed(data.code, data.message)
        break
      case "run_error_alert":
        showRunErrorAlert(this, data)
        break
      case "conversation_queue_updated":
        handleQueueUpdatedEvent(this, data)
        break
    }
  }

  /**
   * Handle queue update broadcasts.
   *
   * Dispatches a window event with the new scheduling state so that
   * message_form_controller can update the input locked state.
   *
   * @param {Object} data - Queue update data with scheduling_state
   */
  handleQueueUpdated(data) {
    handleQueueUpdatedEvent(this, data)
  }

  /**
   * Show the typing indicator with correct styling.
   */
  showTypingIndicator(data) {
    showTypingIndicator(this, data)
  }

  /**
   * Hide the typing indicator.
   */
  hideTypingIndicator(participantId = null) {
    hideTypingIndicator(this, participantId)
  }

  /**
   * Update the typing indicator with streaming content.
   */
  updateTypingContent(content, participantId = null) {
    updateTypingContent(this, content, participantId)
  }

  // ============================================================================
  // Stuck Run Detection
  // ============================================================================

  /**
   * Start stuck detection timer.
   * If no chunks received after threshold, show stuck warning.
   */
  startStuckDetection() {
    startStuckDetection(this)
  }

  clearStuckTimeout() {
    clearStuckTimeout(this)
  }

  /**
   * Show warning that the run appears to be stuck.
   */
  showStuckWarning() {
    showStuckWarning(this)
  }

  /**
   * Hide the stuck warning.
   */
  hideStuckWarning() {
    hideStuckWarning(this)
  }

  /**
   * Handle cancel button click in stuck warning - with confirmation.
   */
  confirmCancelStuckRun(event) {
    confirmCancelStuckRun(this, event)
  }

  /**
   * Handle cancel button click in stuck warning.
   * Sends request to cancel_stuck_run endpoint.
   */
  async cancelStuckRun(event) {
    await cancelStuckRun(this, event)
  }

  /**
   * Handle retry button click in stuck warning.
   * Sends request to retry_stuck_run endpoint.
   */
  async retryStuckRun(event) {
    await retryStuckRun(this, event)
  }

  // ============================================================================
  // Run Error Alert (blocking error that requires user action)
  // ============================================================================

  /**
   * Show the run error alert when a run fails and blocks progress.
   * This is different from stuck warning - it appears when the run has already failed
   * and the conversation cannot continue without user intervention.
   */
  showRunErrorAlert(data) {
    showRunErrorAlert(this, data)
  }

  /**
   * Hide the run error alert.
   */
  hideRunErrorAlert() {
    hideRunErrorAlert(this)
  }

  /**
   * Handle retry button click in the error alert.
   * Retries the failed run.
   */
  async retryFailedRun(event) {
    await retryFailedRun(this, event)
  }

  /**
   * Handle stream completion.
   * The actual message will appear via Turbo Streams.
   */
  handleStreamComplete(participantId = null) {
    handleStreamComplete(this, participantId)
  }

  /**
   * Handle run skipped event.
   * Shows a warning toast when a run was skipped (e.g., due to state change).
   */
  handleRunSkipped(reason, message = null) {
    handleRunSkipped(reason, message)
  }

  /**
   * Handle run canceled event.
   * Shows an info toast when generation was stopped by the user.
   */
  handleRunCanceled() {
    handleRunCanceled()
  }

  /**
   * Handle run failed event.
   * Shows an error toast with the failure message.
   */
  handleRunFailed(code, message) {
    handleRunFailed(code, message)
  }

  /**
   * Get a user-friendly message for a skip reason code.
   */
  getSkippedReasonMessage(reason) {
    return getSkippedReasonMessage(reason)
  }

  resetTimeout() {
    resetTypingTimeout(this)
  }

  clearTimeout() {
    clearTypingTimeout(this)
  }

  scrollToTypingIndicator() {
    scrollToTypingIndicator(this)
  }

  // ============================================================================
  // Periodic Health Check
  // ============================================================================

  /**
   * Start periodic health check polling.
   * Checks conversation health every `healthCheckIntervalValue` milliseconds.
   */
  startHealthCheck() {
    startHealthCheck(this)
  }

  /**
   * Stop health check polling.
   */
  stopHealthCheck() {
    stopHealthCheck(this)
  }

  /**
   * Perform a health check and update UI accordingly.
   */
  async performHealthCheck() {
    await performHealthCheck(this)
  }

  /**
   * Handle health status response and update UI.
   */
  handleHealthStatus(health) {
    handleHealthStatus(this, health)
  }

  // ============================================================================
  // Idle Alert (no run when there should be)
  // ============================================================================

  /**
   * Show idle alert when conversation should be active but isn't.
   */
  showIdleAlert(details) {
    showIdleAlert(this, details)
  }

  /**
   * Hide the idle alert.
   */
  hideIdleAlert() {
    hideIdleAlert(this)
  }

  /**
   * Handle generate button click in idle alert.
   * Triggers a new AI response.
   */
  async generateFromIdleAlert(event) {
    await generateFromIdleAlert(this, event)
  }
}
