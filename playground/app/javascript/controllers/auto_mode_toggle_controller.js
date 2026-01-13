import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { AUTO_MODE_DISABLED_EVENT, USER_TYPING_DISABLE_AUTO_MODE_EVENT } from "../chat/events"
import { disableUntilReplaced, showToast, showToastIfNeeded, turboPost, withRequestLock } from "../request_helpers"

/**
 * Auto Mode Toggle Controller
 *
 * Handles starting/stopping auto-mode for AI-to-AI conversation in group chats.
 * Auto-mode allows AI characters to take turns automatically without requiring
 * user intervention.
 *
 * Features:
 * - Start auto-mode with a configurable number of rounds (default: 4)
 * - Stop auto-mode immediately
 * - Real-time UI updates via Turbo Streams
 * - Toast notifications for user feedback
 *
 * @example HTML structure
 *   <div data-controller="auto-mode-toggle"
 *        data-auto-mode-toggle-url-value="/conversations/123/toggle_auto_mode"
 *        data-auto-mode-toggle-default-rounds-value="4">
 *     <button data-action="click->auto-mode-toggle#start">Start</button>
 *     <button data-action="click->auto-mode-toggle#stop">Stop</button>
 *   </div>
 */
export default class extends Controller {
  static targets = ["button", "button1", "icon", "count"]

  static values = {
    url: String,
    defaultRounds: { type: Number, default: 4 },
    enabled: { type: Boolean, default: false }
  }

  connect() {
    this.handleUserTypingDisable = this.handleUserTypingDisable.bind(this)
    this.handleAutoModeDisabled = this.handleAutoModeDisabled.bind(this)
    window.addEventListener(USER_TYPING_DISABLE_AUTO_MODE_EVENT, this.handleUserTypingDisable)
    window.addEventListener(AUTO_MODE_DISABLED_EVENT, this.handleAutoModeDisabled)
  }

  disconnect() {
    window.removeEventListener(USER_TYPING_DISABLE_AUTO_MODE_EVENT, this.handleUserTypingDisable)
    window.removeEventListener(AUTO_MODE_DISABLED_EVENT, this.handleAutoModeDisabled)
  }

  /**
   * Handle event when Auto mode is disabled by another action (e.g., Copilot enabled).
   * Updates UI without server request since the server already handled it.
   */
  handleAutoModeDisabled(event) {
    const _remainingRounds = event?.detail?.remainingRounds || 0
    this.enabledValue = false
    this.updateButtonUI(false, this.defaultRoundsValue)
  }

  /**
   * Handle user typing event - disable Auto mode when user starts typing.
   * This prevents race conditions where both user and AI messages are sent.
   */
  handleUserTypingDisable() {
    // Only act if Auto mode is currently enabled
    if (!this.enabledValue) return

    // Disable Auto mode
    this.disableAutoModeDueToUserTyping()
  }

  /**
   * Disable Auto mode because user started typing.
   */
  async disableAutoModeDueToUserTyping() {
    await withRequestLock(this.urlValue, async () => {
      // Update local state
      this.enabledValue = false

      // Immediately update button UI
      this.updateButtonUI(false, this.defaultRoundsValue)

      const success = await this.toggleAutoMode(0)
      if (success) {
        showToast("Auto mode disabled - you are typing", "info")
        return
      }

      // Revert UI state on failure.
      this.enabledValue = true
      this.updateButtonUI(true, this.defaultRoundsValue)
    })
  }

  /**
   * Start auto-mode with the default number of rounds.
   */
  async start(event) {
    event.preventDefault()

    const button = event.currentTarget || (this.hasButtonTarget ? this.buttonTarget : null)

    await withRequestLock(this.urlValue, async () => {
      await disableUntilReplaced(button, async () => {
        this.enabledValue = true
        this.updateButtonUI(true, this.defaultRoundsValue)

        const success = await this.toggleAutoMode(this.defaultRoundsValue)
        if (!success) {
          // Revert UI state on failure
          this.enabledValue = false
          this.updateButtonUI(false, this.defaultRoundsValue)
        }

        return success
      })
    })
  }

  /**
   * Start auto-mode with just 1 round (skip current turn once).
   */
  async startOne(event) {
    event.preventDefault()

    const button = event.currentTarget || (this.hasButton1Target ? this.button1Target : null)

    await withRequestLock(this.urlValue, async () => {
      await disableUntilReplaced(button, async () => {
        this.enabledValue = true
        this.updateButtonUI(true, 1)

        const success = await this.toggleAutoMode(1)
        if (!success) {
          // Revert UI state on failure
          this.enabledValue = false
          this.updateButtonUI(false, this.defaultRoundsValue)
        }

        return success
      })
    })
  }

  /**
   * Stop auto-mode immediately.
   */
  async stop(event) {
    event.preventDefault()

    const button = event.currentTarget || (this.hasButtonTarget ? this.buttonTarget : null)

    await withRequestLock(this.urlValue, async () => {
      await disableUntilReplaced(button, async () => {
        this.enabledValue = false
        this.updateButtonUI(false, this.defaultRoundsValue)

        const success = await this.toggleAutoMode(0)
        if (!success) {
          // Revert UI state on failure
          this.enabledValue = true
          this.updateButtonUI(true, this.defaultRoundsValue)
        }

        return success
      })
    })
  }

  /**
   * Immediately update button UI for responsive feedback.
   * @param {boolean} active - Whether auto-mode is active
   * @param {number} rounds - Number of rounds to display
   */
  updateButtonUI(active, rounds) {
    if (!this.hasButtonTarget) return

    const btn = this.buttonTarget

    if (active) {
      // Switch to active (success) state with pause icon
      btn.classList.remove("btn-ghost")
      btn.classList.add("btn-success")
      btn.dataset.action = "click->auto-mode-toggle#stop"

      if (this.hasIconTarget) {
        // Remove all possible inactive icons
        this.iconTarget.classList.remove("icon-[lucide--play]", "icon-[lucide--fast-forward]")
        this.iconTarget.classList.add("icon-[lucide--pause]")
      }

      // Hide the skip-1 button when active
      if (this.hasButton1Target) {
        this.button1Target.classList.add("hidden")
      }
    } else {
      // Switch to inactive (ghost) state with fast-forward icon
      btn.classList.remove("btn-success")
      btn.classList.add("btn-ghost")
      btn.dataset.action = "click->auto-mode-toggle#start"

      if (this.hasIconTarget) {
        this.iconTarget.classList.remove("icon-[lucide--pause]")
        this.iconTarget.classList.add("icon-[lucide--fast-forward]")
      }

      // Show the skip-1 button when inactive
      if (this.hasButton1Target) {
        this.button1Target.classList.remove("hidden")
      }
    }

    // Update count display
    if (this.hasCountTarget) {
      this.countTarget.textContent = rounds
    }
  }

  /**
   * Send toggle request to the server.
   *
   * @param {number} rounds - Number of rounds (0 to stop)
   * @returns {boolean} - Whether the request was successful
   */
  async toggleAutoMode(rounds) {
    if (!this.hasUrlValue) {
      logger.error("Auto-mode toggle URL not configured")
      return false
    }

    try {
      const { response, toastAlreadyShown } = await turboPost(this.urlValue, {
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `rounds=${rounds}`
      })

      if (!response.ok) {
        logger.error("Failed to toggle auto-mode:", response.status)

        showToastIfNeeded(toastAlreadyShown, rounds > 0 ? "Failed to start auto-mode" : "Failed to stop auto-mode", "error")
        return false
      }
      return true
    } catch (error) {
      logger.error("Failed to toggle auto-mode:", error)
      showToast("Failed to toggle auto-mode", "error")
      return false
    }
  }
}
