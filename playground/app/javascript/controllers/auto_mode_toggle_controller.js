import { Controller } from "@hotwired/stimulus"

// Global processing state - survives Turbo Stream replacements that reinitialize the controller
// Key: URL value, Value: boolean
const processingStates = new Map()

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
    window.addEventListener("user:typing:disable-auto-mode", this.handleUserTypingDisable)
    window.addEventListener("auto-mode:disabled", this.handleAutoModeDisabled)
  }

  disconnect() {
    window.removeEventListener("user:typing:disable-auto-mode", this.handleUserTypingDisable)
    window.removeEventListener("auto-mode:disabled", this.handleAutoModeDisabled)
  }

  // Use global state to survive Turbo Stream replacements
  get isProcessing() {
    return processingStates.get(this.urlValue) || false
  }

  set isProcessing(value) {
    if (value) {
      processingStates.set(this.urlValue, true)
    } else {
      processingStates.delete(this.urlValue)
    }
  }

  /**
   * Handle event when Auto mode is disabled by another action (e.g., Copilot enabled).
   * Updates UI without server request since the server already handled it.
   */
  handleAutoModeDisabled(event) {
    const remainingRounds = event?.detail?.remainingRounds || 0
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
    // Update local state
    this.enabledValue = false

    // Immediately update button UI
    this.updateButtonUI(false, this.defaultRoundsValue)

    // Send request to disable
    await this.toggleAutoMode(0)

    // Show toast
    this.showToast("Auto mode disabled - you are typing", "info")
  }

  /**
   * Start auto-mode with the default number of rounds.
   */
  async start(event) {
    event.preventDefault()
    
    // Prevent rapid clicking race conditions
    if (this.isProcessing) return
    this.isProcessing = true
    
    this.enabledValue = true
    this.updateButtonUI(true, this.defaultRoundsValue)
    
    try {
      const success = await this.toggleAutoMode(this.defaultRoundsValue)
      if (!success) {
        // Revert UI state on failure
        this.enabledValue = false
        this.updateButtonUI(false, this.defaultRoundsValue)
      }
    } finally {
      this.isProcessing = false
    }
  }

  /**
   * Start auto-mode with just 1 round (skip current turn once).
   */
  async startOne(event) {
    event.preventDefault()
    
    // Prevent rapid clicking race conditions
    if (this.isProcessing) return
    this.isProcessing = true
    
    this.enabledValue = true
    this.updateButtonUI(true, 1)
    
    try {
      const success = await this.toggleAutoMode(1)
      if (!success) {
        // Revert UI state on failure
        this.enabledValue = false
        this.updateButtonUI(false, this.defaultRoundsValue)
      }
    } finally {
      this.isProcessing = false
    }
  }

  /**
   * Stop auto-mode immediately.
   */
  async stop(event) {
    event.preventDefault()
    
    // Prevent rapid clicking race conditions
    if (this.isProcessing) return
    this.isProcessing = true
    
    this.enabledValue = false
    this.updateButtonUI(false, this.defaultRoundsValue)
    
    try {
      const success = await this.toggleAutoMode(0)
      if (!success) {
        // Revert UI state on failure
        this.enabledValue = true
        this.updateButtonUI(true, this.defaultRoundsValue)
      }
    } finally {
      this.isProcessing = false
    }
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
      console.error("Auto-mode toggle URL not configured")
      return false
    }

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfToken,
          "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
        },
        body: `rounds=${rounds}`
      })

      if (!response.ok) {
        const errorText = await response.text()
        console.error("Failed to toggle auto-mode:", response.status, errorText)

        // Show error toast
        this.showToast(
          rounds > 0
            ? "Failed to start auto-mode"
            : "Failed to stop auto-mode",
          "error"
        )
        return false
      }
      // Turbo will handle the stream response and update the UI
      return true
    } catch (error) {
      console.error("Failed to toggle auto-mode:", error)
      this.showToast("Failed to toggle auto-mode", "error")
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
