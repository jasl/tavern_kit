import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { disableUntilReplaced, showToast, showToastIfNeeded, turboPost, withRequestLock } from "../request_helpers"

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

  /**
   * Pause the active round.
   * If a generation is in progress, the pause will take effect after it completes.
   */
  async pause(event) {
    event.preventDefault()

    const lockKey = this.pauseUrlValue || this.resumeUrlValue
    const button = this.hasButtonTarget ? this.buttonTarget : null

    await withRequestLock(lockKey, async () => {
      await disableUntilReplaced(button, () => this.sendRequest(this.pauseUrlValue))
    })
  }

  /**
   * Resume the paused round.
   * Schedules the next speaker to continue the round.
   */
  async resume(event) {
    event.preventDefault()

    if (this.resumeBlockedValue) return

    const lockKey = this.pauseUrlValue || this.resumeUrlValue
    const button = this.hasButtonTarget ? this.buttonTarget : null

    await withRequestLock(lockKey, async () => {
      await disableUntilReplaced(button, () => this.sendRequest(this.resumeUrlValue))
    })
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
      const { response, toastAlreadyShown } = await turboPost(url, {
        headers: { "Content-Type": "application/x-www-form-urlencoded" }
      })

      if (!response.ok) {
        logger.error("Pause toggle request failed:", response.status)

        showToastIfNeeded(toastAlreadyShown, this.pausedValue ? "Failed to resume" : "Failed to pause", "error")
        return false
      }

      return true
    } catch (error) {
      logger.error("Pause toggle request failed:", error)
      showToast("Request failed", "error")
      return false
    }
  }
}
