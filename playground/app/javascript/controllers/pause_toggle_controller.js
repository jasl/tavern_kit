import { Controller } from "@hotwired/stimulus"
import logger from "../logger"

// Global processing state - survives Turbo Stream replacements that reinitialize the controller
// Key: pause URL value, Value: boolean
const processingStates = new Map()

/**
 * Pause Toggle Controller
 *
 * Handles pausing/resuming the TurnScheduler round in group chats.
 * Pause preserves the active round and speaker order so it can be resumed later.
 *
 * Features:
 * - Toggle between Pause and Resume states
 * - Immediate button disable on click for responsive feedback
 * - Handles "pausing" state when generation is still in progress
 * - Real-time UI updates via Turbo Streams
 * - Toast notifications for user feedback
 *
 * @example HTML structure
 *   <div data-controller="pause-toggle"
 *        data-pause-toggle-pause-url-value="/conversations/123/pause_round"
 *        data-pause-toggle-resume-url-value="/conversations/123/resume_round"
 *        data-pause-toggle-paused-value="false"
 *        data-pause-toggle-resume-blocked-value="false">
 *     <button data-pause-toggle-target="button"
 *             data-action="click->pause-toggle#pause">Pause</button>
 *   </div>
 */
export default class extends Controller {
  static targets = ["button"]

  static values = {
    pauseUrl: String,
    resumeUrl: String,
    paused: { type: Boolean, default: false },
    resumeBlocked: { type: Boolean, default: false }
  }

  connect() {
    // Controller is ready
  }

  disconnect() {
    // Cleanup if needed
  }

  // Use global state to survive Turbo Stream replacements
  get isProcessing() {
    return processingStates.get(this.pauseUrlValue) || false
  }

  set isProcessing(value) {
    if (value) {
      processingStates.set(this.pauseUrlValue, true)
    } else {
      processingStates.delete(this.pauseUrlValue)
    }
  }

  /**
   * Pause the active round.
   * If a generation is in progress, the pause will take effect after it completes.
   */
  async pause(event) {
    event.preventDefault()

    // Prevent rapid clicking race conditions
    if (this.isProcessing) return
    this.isProcessing = true

    // Immediately disable button for responsive feedback
    this.disableButton()

    try {
      const success = await this.sendRequest(this.pauseUrlValue)
      if (!success) {
        // Revert UI state on failure
        this.enableButton()
      }
      // On success, Turbo Stream will replace the element with paused state
    } finally {
      this.isProcessing = false
    }
  }

  /**
   * Resume the paused round.
   * Schedules the next speaker to continue the round.
   */
  async resume(event) {
    event.preventDefault()

    // Prevent rapid clicking or clicking while resume is blocked
    if (this.isProcessing) return
    if (this.resumeBlockedValue) return
    this.isProcessing = true

    // Immediately disable button for responsive feedback
    this.disableButton()

    try {
      const success = await this.sendRequest(this.resumeUrlValue)
      if (!success) {
        // Revert UI state on failure
        this.enableButton()
      }
      // On success, Turbo Stream will replace the element with ai_generating state
    } finally {
      this.isProcessing = false
    }
  }

  /**
   * Disable the button for immediate feedback.
   */
  disableButton() {
    if (!this.hasButtonTarget) return
    this.buttonTarget.disabled = true
  }

  /**
   * Re-enable the button (used on failure).
   */
  enableButton() {
    if (!this.hasButtonTarget) return
    this.buttonTarget.disabled = false
  }

  /**
   * Send request to the server.
   *
   * @param {string} url - The endpoint URL
   * @returns {boolean} - Whether the request was successful
   */
  async sendRequest(url) {
    if (!url) {
      logger.error("Pause toggle URL not configured")
      return false
    }

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfToken,
          "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
        }
      })

      if (!response.ok) {
        const errorText = await response.text()
        logger.error("Pause toggle request failed:", response.status, errorText)

        // Show error toast
        this.showToast(
          this.pausedValue ? "Failed to resume" : "Failed to pause",
          "error"
        )
        return false
      }

      return true
    } catch (error) {
      logger.error("Pause toggle request failed:", error)
      this.showToast("Request failed", "error")
      return false
    }
  }

  /**
   * Show a toast notification.
   */
  showToast(message, type = "info") {
    window.dispatchEvent(new CustomEvent("toast:show", {
      detail: { message, type, duration: 3000 },
      bubbles: true,
      cancelable: true
    }))
  }

  /**
   * Get CSRF token from meta tag.
   */
  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
