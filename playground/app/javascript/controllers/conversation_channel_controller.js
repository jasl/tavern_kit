import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import logger from "../logger"
import { setCableConnected } from "../conversation_state"
import { CABLE_CONNECTED_EVENT, CABLE_DISCONNECTED_EVENT, SCHEDULING_STATE_CHANGED_EVENT, dispatchWindowEvent } from "../chat/events"
import { jsonRequest, showToast, showToastIfNeeded, turboPost, turboRequest } from "../request_helpers"

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
    this.setupMessagesObserver()

    // Prevent duplicate message appends.
    // User messages are delivered twice: via HTTP response (reliable for sender)
    // and via ActionCable broadcast (for other users). This handler prevents
    // the sender from seeing duplicates.
    this.setupDuplicateMessagePrevention()

    // Start periodic health check
    this.startHealthCheck()
  }

  disconnect() {
    this.manualDisconnect = true
    this.unsubscribeFromChannel()
    this.clearTimeout()
    this.clearStuckTimeout()
    this.stopHealthCheck()
    this.disconnectMessagesObserver()
    this.teardownDuplicateMessagePrevention()
  }

  /**
   * Subscribe to ConversationChannel for all JSON events.
   */
  async subscribeToChannel() {
    const conversationId = this.conversationValue
    if (!conversationId) return

    try {
      this.manualDisconnect = false
      this.channel = await cable.subscribeTo(
        { channel: "ConversationChannel", conversation_id: conversationId },
        {
          received: this.handleMessage.bind(this),
          connected: this.handleChannelConnected.bind(this),
          disconnected: this.handleChannelDisconnected.bind(this),
          rejected: this.handleChannelRejected.bind(this)
        }
      )
    } catch (error) {
      logger.warn("Failed to subscribe to ConversationChannel:", error)
    }
  }

  unsubscribeFromChannel() {
    this.channel?.unsubscribe()
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

  messagesList() {
    return this.element.querySelector("[data-chat-scroll-target='list']")
  }

  setupMessagesObserver() {
    const list = this.messagesList()
    if (!list) return

    this.messagesObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type !== "childList" || mutation.addedNodes.length === 0) continue

        // Only react to appends at the end of the list.
        // (Prepending older history for infinite scroll should not clear the indicator.)
        if (mutation.nextSibling !== null) continue

        const appendedMessage = Array.from(mutation.addedNodes).some((node) => {
          return node.nodeType === Node.ELEMENT_NODE
            && typeof node.id === "string"
            && node.id.startsWith("message_")
        })

        if (appendedMessage) {
          this.hideTypingIndicator()
          this.hideRunErrorAlert() // Also clear error alert when message appears
          break
        }
      }
    })

    this.messagesObserver.observe(list, {
      childList: true,
      subtree: false
    })
  }

  disconnectMessagesObserver() {
    if (this.messagesObserver) {
      this.messagesObserver.disconnect()
      this.messagesObserver = null
    }
  }

  /**
   * Set up duplicate message prevention for Turbo Stream appends.
   *
   * User messages are delivered twice:
   * 1. Via HTTP Turbo Stream response (reliable for sender during WebSocket reconnection)
   * 2. Via ActionCable broadcast (for all subscribers including sender)
   *
   * This handler intercepts Turbo Stream append actions and prevents duplicates
   * by checking if the message element already exists in the DOM.
   */
  setupDuplicateMessagePrevention() {
    this.handleTurboStreamRender = (event) => {
      const fallbackToDefaultActions = event.detail.render

      event.detail.render = (streamElement) => {
        const action = streamElement.getAttribute("action")

        // Only intercept append actions for messages
        if (action === "append") {
          const template = streamElement.querySelector("template")
          if (template) {
            const content = template.content.firstElementChild
            // Check if this is a message element and it already exists
            if (content && content.id && content.id.startsWith("message_")) {
              const existingElement = document.getElementById(content.id)
              if (existingElement) {
                // Skip this append - message already exists
                return
              }
            }
          }
        }

        // Fall back to default Turbo Stream behavior
        fallbackToDefaultActions(streamElement)
      }
    }

    document.addEventListener("turbo:before-stream-render", this.handleTurboStreamRender)
  }

  teardownDuplicateMessagePrevention() {
    if (this.handleTurboStreamRender) {
      document.removeEventListener("turbo:before-stream-render", this.handleTurboStreamRender)
      this.handleTurboStreamRender = null
    }
  }

  /**
   * Handle incoming ActionCable messages.
   */
  handleMessage(data) {
    if (!data || !data.type) return

    switch (data.type) {
      case "typing_start":
        this.showTypingIndicator(data)
        break
      case "typing_stop":
        this.hideTypingIndicator(data.space_membership_id)
        break
      case "stream_chunk":
        this.updateTypingContent(data.content, data.space_membership_id)
        break
      case "stream_complete":
        this.handleStreamComplete(data.space_membership_id)
        break
      case "run_skipped":
        this.handleRunSkipped(data.reason, data.message)
        break
      case "run_canceled":
        this.handleRunCanceled()
        break
      case "run_failed":
        this.handleRunFailed(data.code, data.message)
        break
      case "run_error_alert":
        this.showRunErrorAlert(data)
        break
      case "conversation_queue_updated":
        this.handleQueueUpdated(data)
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
    const { scheduling_state: schedulingState, group_queue_revision: groupQueueRevision } = data
    const revision = Number(groupQueueRevision)

    // In multi-process setups, ActionCable events can arrive out of order.
    // Use the server-side monotonic revision (shared with Turbo updates) to ignore stale events.
    if (Number.isFinite(revision)) {
      if (Number.isFinite(this.lastQueueRevision) && revision <= this.lastQueueRevision) {
        return
      }
      this.lastQueueRevision = revision
    }

    if (schedulingState) {
      dispatchWindowEvent(SCHEDULING_STATE_CHANGED_EVENT, { schedulingState, conversationId: this.conversationValue })
    }
  }

  /**
   * Show the typing indicator with correct styling.
   */
  showTypingIndicator(data) {
    const {
      name = "AI",
      space_membership_id: spaceMembershipId,
      avatar_url: avatarUrl
    } = data

    this.currentSpaceMembershipId = spaceMembershipId
    this.lastChunkAt = Date.now()

    if (this.hasTypingNameTarget) {
      this.typingNameTarget.textContent = name
    }

    if (this.hasTypingContentTarget) {
      this.typingContentTarget.textContent = ""
    }

    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.classList.remove("hidden")
    }

    if (this.hasTypingAvatarImgTarget && avatarUrl) {
      this.typingAvatarImgTarget.src = avatarUrl
      this.typingAvatarImgTarget.alt = name
    }

    this.hideStuckWarning()
    this.resetTimeout()
    this.startStuckDetection()
    this.scrollToTypingIndicator()
  }

  /**
   * Hide the typing indicator.
   */
  hideTypingIndicator(participantId = null) {
    if (participantId && this.currentSpaceMembershipId && participantId !== this.currentSpaceMembershipId) {
      return
    }

    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.classList.add("hidden")
    }

    if (this.hasTypingContentTarget) {
      this.typingContentTarget.textContent = ""
    }

    this.currentSpaceMembershipId = null
    this.lastChunkAt = null
    this.clearTimeout()
    this.clearStuckTimeout()
    this.hideStuckWarning()
  }

  /**
   * Update the typing indicator with streaming content.
   */
  updateTypingContent(content, participantId = null) {
    if (participantId && this.currentSpaceMembershipId && participantId !== this.currentSpaceMembershipId) {
      return
    }

    if (this.hasTypingContentTarget && typeof content === "string") {
      this.typingContentTarget.textContent = content
    }

    // Update last chunk time and restart stuck detection
    this.lastChunkAt = Date.now()
    this.hideStuckWarning()
    this.startStuckDetection()

    this.resetTimeout()
    this.scrollToTypingIndicator()
  }

  // ============================================================================
  // Stuck Run Detection
  // ============================================================================

  /**
   * Start stuck detection timer.
   * If no chunks received after threshold, show stuck warning.
   */
  startStuckDetection() {
    this.clearStuckTimeout()
    this.stuckTimeoutId = setTimeout(() => {
      this.showStuckWarning()
    }, this.stuckThresholdValue)
  }

  clearStuckTimeout() {
    if (this.stuckTimeoutId) {
      clearTimeout(this.stuckTimeoutId)
      this.stuckTimeoutId = null
    }
  }

  /**
   * Show warning that the run appears to be stuck.
   */
  showStuckWarning() {
    if (this.hasStuckWarningTarget) {
      this.stuckWarningTarget.classList.remove("hidden")
    }
  }

  /**
   * Hide the stuck warning.
   */
  hideStuckWarning() {
    if (this.hasStuckWarningTarget) {
      this.stuckWarningTarget.classList.add("hidden")
    }
  }

  /**
   * Handle cancel button click in stuck warning - with confirmation.
   */
  confirmCancelStuckRun(event) {
    event.preventDefault()

    const confirmed = confirm(
      "Cancel this AI response?\n\n" +
      "This will stop the current generation and may affect the conversation flow. " +
      "You can use 'Retry' to try again instead."
    )

    if (confirmed) {
      this.cancelStuckRun(event)
    }
  }

  /**
   * Handle cancel button click in stuck warning.
   * Sends request to cancel_stuck_run endpoint.
   */
  async cancelStuckRun(event) {
    event.preventDefault()

    const url = this.cancelUrlValue
    if (!url) {
      logger.warn("No cancel URL configured")
      return
    }

    try {
      const { response, toastAlreadyShown } = await turboPost(url)

      if (response.ok) {
        this.hideTypingIndicator()
        this.hideStuckWarning()
      } else {
        showToastIfNeeded(toastAlreadyShown, "Failed to cancel run. Please try again.", "error")
      }
    } catch (error) {
      logger.error("Error canceling stuck run:", error)
      showToast("Failed to cancel run. Please try again.", "error")
    }
  }

  /**
   * Handle retry button click in stuck warning.
   * Sends request to retry_stuck_run endpoint.
   */
  async retryStuckRun(event) {
    event.preventDefault()

    const url = this.retryUrlValue
    if (!url) {
      logger.warn("No retry URL configured")
      return
    }

    // Hide stuck warning immediately
    this.hideStuckWarning()
    // Reset stuck timer
    this.lastChunkAt = Date.now()

    try {
      const { response, toastAlreadyShown } = await turboPost(url)

      if (!response.ok) {
        showToastIfNeeded(toastAlreadyShown, "Failed to retry run. Please try again.", "error")
        this.showStuckWarning()
      }
    } catch (error) {
      logger.error("Error retrying stuck run:", error)
      showToast("Failed to retry run. Please try again.", "error")
      this.showStuckWarning()
    }
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
    const { run_id: runId, message } = data

    // Store the failed run ID for retry
    this.failedRunId = runId

    // Hide typing indicator since the run has failed
    this.hideTypingIndicator()
    this.hideStuckWarning()

    // Show the error alert with the message
    if (this.hasRunErrorMessageTarget) {
      this.runErrorMessageTarget.textContent = message || "AI response failed. Click Retry to try again. Sending a new message will reset the round (Auto mode/Copilot will be turned off)."
    }

    if (this.hasRunErrorAlertTarget) {
      this.runErrorAlertTarget.classList.remove("hidden")
    }
  }

  /**
   * Hide the run error alert.
   */
  hideRunErrorAlert() {
    if (this.hasRunErrorAlertTarget) {
      this.runErrorAlertTarget.classList.add("hidden")
    }
    this.failedRunId = null
  }

  /**
   * Handle retry button click in the error alert.
   * Retries the failed run.
   */
  async retryFailedRun(event) {
    event.preventDefault()

    const url = this.retryUrlValue
    if (!url) {
      logger.warn("No retry URL configured")
      return
    }

    // Hide the error alert immediately
    this.hideRunErrorAlert()

    try {
      const { response, toastAlreadyShown } = await turboPost(url)

      if (!response.ok) {
        showToastIfNeeded(toastAlreadyShown, "Failed to retry. Please try again.", "error")
        // Re-show the error alert since retry failed
        if (this.hasRunErrorAlertTarget) {
          this.runErrorAlertTarget.classList.remove("hidden")
        }
      }
    } catch (error) {
      logger.error("Error retrying failed run:", error)
      showToast("Failed to retry. Please try again.", "error")
      // Re-show the error alert since retry failed
      if (this.hasRunErrorAlertTarget) {
        this.runErrorAlertTarget.classList.remove("hidden")
      }
    }
  }

  /**
   * Handle stream completion.
   * The actual message will appear via Turbo Streams.
   */
  handleStreamComplete(participantId = null) {
    setTimeout(() => {
      this.hideTypingIndicator(participantId)
    }, 100)
  }

  /**
   * Handle run skipped event.
   * Shows a warning toast when a run was skipped (e.g., due to state change).
   */
  handleRunSkipped(reason, message = null) {
    const toastMessage = message || this.getSkippedReasonMessage(reason)
    showToast(toastMessage, "warning")
  }

  /**
   * Handle run canceled event.
   * Shows an info toast when generation was stopped by the user.
   */
  handleRunCanceled() {
    showToast("Stopped.", "info")
  }

  /**
   * Handle run failed event.
   * Shows an error toast with the failure message.
   */
  handleRunFailed(code, message) {
    const toastMessage = message || "Generation failed. Please try again."
    showToast(toastMessage, "error")
  }

  /**
   * Get a user-friendly message for a skip reason code.
   */
  getSkippedReasonMessage(reason) {
    const messages = {
      "message_mismatch": "Skipped: conversation has changed since your request.",
      "state_changed": "Skipped: conversation state changed.",
    }
    return messages[reason] || "Operation skipped due to a state change."
  }

  resetTimeout() {
    this.clearTimeout()
    this.timeoutId = setTimeout(() => {
      this.hideTypingIndicator()
    }, this.timeoutValue)
  }

  clearTimeout() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
      this.timeoutId = null
    }
  }

  scrollToTypingIndicator() {
    const messagesContainer = this.element.closest("[data-chat-scroll-target='messages']")
      || document.querySelector("[data-chat-scroll-target='messages']")

    if (messagesContainer) {
      requestAnimationFrame(() => {
        messagesContainer.scrollTo({
          top: messagesContainer.scrollHeight,
          behavior: "smooth"
        })
      })
    }
  }

  // ============================================================================
  // Periodic Health Check
  // ============================================================================

  /**
   * Start periodic health check polling.
   * Checks conversation health every `healthCheckIntervalValue` milliseconds.
   */
  startHealthCheck() {
    if (!this.healthUrlValue) return

    // Do an initial check after a short delay
    setTimeout(() => this.performHealthCheck(), 5000)

    // Then check periodically
    this.healthCheckIntervalId = setInterval(
      () => this.performHealthCheck(),
      this.healthCheckIntervalValue
    )
  }

  /**
   * Stop health check polling.
   */
  stopHealthCheck() {
    if (this.healthCheckIntervalId) {
      clearInterval(this.healthCheckIntervalId)
      this.healthCheckIntervalId = null
    }
  }

  /**
   * Perform a health check and update UI accordingly.
   */
  async performHealthCheck() {
    if (!this.healthUrlValue) return

    // Skip health check if typing indicator is visible (we're receiving updates)
    // If the cable is disconnected, polling is our only feedback loop, so do not skip.
    if (this.cableConnected !== false && this.hasTypingIndicatorTarget && !this.typingIndicatorTarget.classList.contains("hidden")) {
      return
    }

    // Skip if error alert is already visible (user needs to act)
    if (this.hasRunErrorAlertTarget && !this.runErrorAlertTarget.classList.contains("hidden")) {
      return
    }

    try {
      const { response, data: health } = await jsonRequest(this.healthUrlValue, {
        method: "GET"
      })

      if (!response.ok || !health) return
      this.handleHealthStatus(health)
    } catch (error) {
      // Silent fail - health check is non-critical
      logger.debug("Health check failed:", error)
    }
  }

  /**
   * Handle health status response and update UI.
   */
  handleHealthStatus(health) {
    const { status, message, action: _action, details } = health

    // Store last status to avoid duplicate alerts
    const statusKey = `${status}:${details?.run_id || "none"}`
    if (this.lastHealthStatus === statusKey) return
    this.lastHealthStatus = statusKey

    switch (status) {
      case "healthy":
        this.hideIdleAlert()
        break

      case "stuck":
        // If run is stuck, show warning via typing indicator if not already visible
        if (this.hasTypingIndicatorTarget && this.typingIndicatorTarget.classList.contains("hidden")) {
          // Show typing indicator with stuck warning directly
          this.showTypingIndicator({
            name: details.speaker_name || "AI",
            space_membership_id: details.speaker_membership_id
          })
        }
        this.showStuckWarning()
        break

      case "failed":
        // Show error alert
        this.showRunErrorAlert({
          run_id: details.run_id,
          message: message
        })
        break

      case "idle_unexpected":
        // Show idle alert with generate button
        this.showIdleAlert(details)
        break
    }
  }

  // ============================================================================
  // Idle Alert (no run when there should be)
  // ============================================================================

  /**
   * Show idle alert when conversation should be active but isn't.
   */
  showIdleAlert(details) {
    if (this.hasIdleAlertMessageTarget) {
      this.idleAlertMessageTarget.textContent = "Conversation seems stuck. No AI is responding."
    }

    if (this.hasIdleAlertSpeakerTarget && details?.suggested_speaker_name) {
      this.idleAlertSpeakerTarget.textContent = details.suggested_speaker_name
      this.idleAlertSpeakerTarget.dataset.speakerId = details.suggested_speaker_id || ""
    }

    if (this.hasIdleAlertTarget) {
      this.idleAlertTarget.classList.remove("hidden")
    }
  }

  /**
   * Hide the idle alert.
   */
  hideIdleAlert() {
    if (this.hasIdleAlertTarget) {
      this.idleAlertTarget.classList.add("hidden")
    }
    // Reset last health status so it can show again if issue persists
    if (this.lastHealthStatus?.startsWith("idle_unexpected")) {
      this.lastHealthStatus = null
    }
  }

  /**
   * Handle generate button click in idle alert.
   * Triggers a new AI response.
   */
  async generateFromIdleAlert(event) {
    event.preventDefault()

    const url = this.generateUrlValue
    if (!url) {
      logger.warn("No generate URL configured")
      return
    }

    // Get suggested speaker if available
    const speakerId = this.hasIdleAlertSpeakerTarget
      ? this.idleAlertSpeakerTarget.dataset.speakerId
      : null

    // Hide the alert immediately
    this.hideIdleAlert()

    try {
      const formData = new FormData()
      if (speakerId) {
        formData.append("speaker_id", speakerId)
      }

      const { response, toastAlreadyShown } = await turboRequest(url, {
        method: "POST",
        body: formData
      })

      if (!response.ok) {
        showToastIfNeeded(toastAlreadyShown, "Failed to generate response. Please try again.", "error")
        this.showIdleAlert({})
      }
    } catch (error) {
      logger.error("Error generating response:", error)
      showToast("Failed to generate response. Please try again.", "error")
      this.showIdleAlert({})
    }
  }
}
