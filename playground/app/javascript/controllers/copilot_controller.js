import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

// Global processing state - survives Turbo Stream replacements that reinitialize the controller
// Key: membership update URL, Value: boolean
const processingStates = new Map()

/**
 * Generate a UUID v4 compatible with all browsers.
 * Uses crypto.randomUUID() if available, otherwise falls back to crypto.getRandomValues(),
 * and finally Math.random() when Web Crypto is unavailable.
 */
function generateUUID() {
  const cryptoObj = typeof crypto !== "undefined" ? crypto : undefined

  if (cryptoObj && typeof cryptoObj.randomUUID === "function") {
    return cryptoObj.randomUUID()
  }

  if (cryptoObj && typeof cryptoObj.getRandomValues === "function") {
    // RFC 4122 section 4.4
    const bytes = new Uint8Array(16)
    cryptoObj.getRandomValues(bytes)
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80

    const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
  }

  // Last resort fallback for environments with no Web Crypto (not cryptographically secure)
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    const v = c === "x" ? r : (r & 0x3) | 0x8
    return v.toString(16)
  })
}

/**
 * Copilot Controller
 *
 * Manages copilot candidate generation and full mode toggle for users
 * with persona characters. Handles:
 * - Generating suggestion candidates via POST request
 * - Receiving candidates via ActionCable
 * - Displaying candidates as clickable buttons
 * - Sending selected candidates
 * - Toggling full/none copilot mode
 *
 * @example HTML structure
 *   <div data-controller="copilot"
 *        data-copilot-url-value="/spaces/123/copilot_candidates"
 *        data-copilot-full-value="false"
 *        data-copilot-membership-id-value="456"
 *        data-copilot-membership-update-url-value="/spaces/123/space_memberships/456">
 *     <div data-copilot-target="candidatesContainer" class="hidden">
 *       <div data-copilot-target="candidatesList"></div>
 *     </div>
 *     <form data-copilot-target="form">
 *       <textarea data-copilot-target="textarea"></textarea>
 *     </form>
 *     <button data-copilot-target="generateBtn" data-action="copilot#generate">Generate</button>
 *     <input type="checkbox" data-copilot-target="fullToggle" data-action="change->copilot#toggleFullMode">
 *   </div>
 */
export default class extends Controller {
  static targets = [
    "candidatesContainer",
    "candidatesList",
    "generateBtn",
    "generateIcon",
    "generateSpinner",
    "generateText",
    "countBtn",
    "textarea",
    "form",
    "sendBtn",
    "fullToggle",
    "stepsCounter"
  ]

  static values = {
    url: String,
    full: Boolean,
    membershipId: Number,
    membershipUpdateUrl: String,
    generationId: String,
    candidateCount: { type: Number, default: 1 },
    generating: { type: Boolean, default: false }
  }

  connect() {
    this.subscribeToChannel()
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleUserTypingDisable = this.handleUserTypingDisable.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
    window.addEventListener("user:typing:disable-copilot", this.handleUserTypingDisable)
    
    // Sync UI state on connect - important after Turbo Stream replacements
    // The fullValue is read from data-copilot-full-value attribute
    this.updateUIForMode()
  }

  // Use global state to survive Turbo Stream replacements
  get isProcessing() {
    return processingStates.get(this.membershipUpdateUrlValue) || false
  }

  set isProcessing(value) {
    if (value) {
      processingStates.set(this.membershipUpdateUrlValue, true)
    } else {
      processingStates.delete(this.membershipUpdateUrlValue)
    }
  }

  disconnect() {
    this.unsubscribeFromChannel()
    document.removeEventListener("keydown", this.handleKeydown)
    window.removeEventListener("user:typing:disable-copilot", this.handleUserTypingDisable)
  }

  /**
   * Handle user typing event - disable Copilot mode when user starts typing.
   * This prevents race conditions where both user and AI messages are sent.
   */
  handleUserTypingDisable() {
    // Only act if Copilot is currently in full mode
    if (!this.fullValue) return

    // Disable Copilot mode
    this.disableCopilotDueToUserTyping()
  }

  /**
   * Disable Copilot mode because user started typing.
   * Similar to toggleFullMode but with specific messaging.
   */
  async disableCopilotDueToUserTyping() {
    // Update local state immediately for responsive UI
    this.fullValue = false
    this.updateUIForMode()
    
    // Reset counter to default steps (what user will see next time they enable)
    if (this.hasStepsCounterTarget && this.hasFullToggleTarget) {
      const defaultSteps = this.fullToggleTarget.dataset?.copilotDefaultSteps || "4"
      this.stepsCounterTarget.textContent = defaultSteps
    }

    // Persist to server
    try {
      const response = await fetch(this.membershipUpdateUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          space_membership: { copilot_mode: "none" }
        })
      })

      if (response.ok) {
        this.showToast("Copilot disabled - you are typing", "info")
      }
      // Silently fail - UI already updated, user is typing
    } catch (error) {
      // Silently fail - UI already updated, user is typing
      console.warn("Failed to disable copilot:", error)
    }
  }

  /**
   * Handle keyboard shortcuts for candidate selection.
   * - 1-4: Select candidate at index (when not typing)
   * - Escape: Clear candidates (always works when visible)
   */
  handleKeydown(event) {
    // Only handle when candidates are visible
    if (!this.areCandidatesVisible()) return

    // Check if user is actively typing in textarea
    const isTyping = this.hasTextareaTarget &&
                     document.activeElement === this.textareaTarget &&
                     this.textareaTarget.value.trim().length > 0

    // Escape: clear candidates (always works, even when typing)
    if (event.key === "Escape") {
      event.preventDefault()
      this.clearCandidates()
      return
    }

    // 1-4: select candidate (only when not actively typing)
    if (!isTyping && event.key >= "1" && event.key <= "4") {
      const index = parseInt(event.key, 10) - 1
      const candidates = this.getCandidateButtons()
      if (candidates[index]) {
        event.preventDefault()
        this.selectCandidateByIndex(index)
      }
    }
  }

  /**
   * Check if candidates container is visible.
   * @returns {boolean}
   */
  areCandidatesVisible() {
    return this.hasCandidatesContainerTarget &&
           !this.candidatesContainerTarget.classList.contains("hidden")
  }

  /**
   * Get all candidate buttons.
   * @returns {HTMLElement[]}
   */
  getCandidateButtons() {
    if (!this.hasCandidatesListTarget) return []
    return Array.from(this.candidatesListTarget.querySelectorAll("button[data-text]"))
  }

  /**
   * Select a candidate by index and fill textarea.
   * @param {number} index - 0-based index
   */
  selectCandidateByIndex(index) {
    const candidates = this.getCandidateButtons()
    if (candidates[index]) {
      const text = candidates[index].dataset.text
      if (this.hasTextareaTarget) {
        this.textareaTarget.value = text
        this.textareaTarget.focus()
      }
      this.clearCandidates()
    }
  }

  /**
   * Subscribe to CopilotChannel for copilot-specific events.
   *
   * Follows Campfire's pattern: each feature has its own dedicated channel.
   * This avoids conflicts with Turbo Streams which use a separate channel.
   *
   * Subscribes per-membership (not per-space) to ensure copilot events are
   * unicast to this user only, preventing data leakage in multi-user spaces.
   */
  async subscribeToChannel() {
    // Extract space ID from URL (supports both /playgrounds/ and /spaces/ paths)
    const match = this.urlValue.match(/(?:playgrounds|spaces)\/(\d+)/)
    if (!match) return

    this.spaceId = parseInt(match[1], 10)

    // Must have membershipId to subscribe (unicast requires membership)
    if (!this.membershipIdValue) {
      console.warn("CopilotChannel: no membership_id, skipping subscription")
      return
    }

    try {
      // Subscribe to the dedicated CopilotChannel (not ConversationChannel)
      // Includes membership_id for per-user unicast streaming
      this.channel = await cable.subscribeTo(
        {
          channel: "CopilotChannel",
          space_id: this.spaceId,
          space_membership_id: this.membershipIdValue
        },
        { received: this.handleMessage.bind(this) }
      )
    } catch (error) {
      console.warn("Failed to subscribe to CopilotChannel:", error)
    }
  }

  unsubscribeFromChannel() {
    this.channel?.unsubscribe()
    this.channel = null
  }

  /**
   * Handle incoming ActionCable messages.
   */
  handleMessage(data) {
    if (!data || !data.type) return

    switch (data.type) {
      case "copilot_candidate":
        this.handleCopilotCandidate(data)
        break
      case "copilot_complete":
        this.handleCopilotComplete(data)
        break
      case "copilot_error":
        this.handleCopilotError(data)
        break
      case "copilot_disabled":
        this.handleCopilotDisabled(data)
        break
      case "copilot_steps_updated":
        this.handleCopilotStepsUpdated(data)
        break
    }
  }

  /**
   * Generate candidate suggestions.
   */
  async generate() {
    if (this.fullValue || this.generatingValue) return

    // Set generating state
    this.generatingValue = true
    this.updateGenerateButtonState()

    // Clear previous candidates
    this.clearCandidates()

    // Generate unique ID for this request
    this.generationIdValue = generateUUID()

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          candidate_count: this.candidateCountValue,
          generation_id: this.generationIdValue
        })
      })

      if (!response.ok) {
        const error = await response.json()
        console.error("Generation failed:", error)
        this.resetGenerateButton()
      }
      // Success: wait for ActionCable events
    } catch (error) {
      console.error("Generation request failed:", error)
      this.resetGenerateButton()
    }
  }

  /**
   * Handle incoming candidate from ActionCable.
   */
  handleCopilotCandidate(data) {
    // Ignore candidates from other generation requests
    if (data.generation_id !== this.generationIdValue) return

    // Show candidates container
    if (this.hasCandidatesContainerTarget) {
      this.candidatesContainerTarget.classList.remove("hidden")
    }

    // Get the candidate template
    const template = document.getElementById("copilot-candidate-template")
    if (!template) {
      console.warn("[copilot] Candidate template not found")
      return
    }

    // Get current count to determine index (1-based display)
    const currentCount = this.getCandidateButtons().length
    const displayIndex = currentCount + 1

    // Clone template and populate
    const btn = template.content.cloneNode(true).firstElementChild
    btn.querySelector("[data-candidate-index]").textContent = displayIndex
    // Use textContent for auto-escaping (prevents XSS)
    btn.querySelector("[data-candidate-text]").textContent = data.text
    btn.dataset.text = data.text

    if (this.hasCandidatesListTarget) {
      this.candidatesListTarget.appendChild(btn)
    }
  }

  /**
   * Handle generation complete from ActionCable.
   */
  handleCopilotComplete(data) {
    if (data.generation_id !== this.generationIdValue) return
    this.resetGenerateButton()
  }

  /**
   * Handle generation error from ActionCable.
   */
  handleCopilotError(data) {
    if (data.generation_id !== this.generationIdValue) return
    console.error("Copilot generation error:", data.error)
    this.resetGenerateButton()
    this.showToast(`Generation failed: ${data.error}`, "error")
  }

  /**
   * Handle full copilot mode disabled (error or exhaustion).
   * Updates UI without page reload for seamless experience.
   */
  handleCopilotDisabled(data) {
    const error = data?.error
    const reason = data?.reason

    console.warn("Copilot mode disabled:", { error, reason })
    
    // Update local state
    this.fullValue = false
    
    // Update UI (unlocks textarea, enables buttons, updates toggle button styling)
    this.updateUIForMode()

    // Reset the counter to default steps for next enable
    if (this.hasStepsCounterTarget && this.hasFullToggleTarget) {
      const defaultSteps = this.fullToggleTarget.dataset?.copilotDefaultSteps || "4"
      this.stepsCounterTarget.textContent = defaultSteps
    }
    
    // Focus textarea for immediate input
    if (this.hasTextareaTarget) {
      this.textareaTarget.focus()
    }
    
    // Show appropriate toast message
    let message = "Copilot disabled."
    let type = "warning"

    if (reason === "remaining_steps_exhausted") {
      message = "Copilot disabled: remaining steps exhausted."
      type = "info"
    } else if (error) {
      message = `Copilot disabled: ${error}`
      type = "warning"
    } else if (reason) {
      message = `Copilot disabled (${reason}).`
      type = "warning"
    }

    this.showToast(message, type)
    // No reload - UI is fully updated
  }

  /**
   * Handle copilot steps updated from ActionCable.
   * Updates the displayed remaining steps count.
   */
  handleCopilotStepsUpdated(data) {
    const remainingSteps = data?.remaining_steps
    if (remainingSteps === undefined || remainingSteps === null) return

    // Update the counter on the toggle button
    if (this.hasStepsCounterTarget) {
      this.stepsCounterTarget.textContent = remainingSteps
    }

    // If steps reach 0, Copilot will be disabled by the server
    // The copilot_disabled event will handle UI updates
  }

  /**
   * Select a candidate and fill the textarea (without auto-submitting).
   * User can review and manually send the message.
   */
  selectCandidate(event) {
    const text = event.currentTarget.dataset.text
    if (!text) return

    // Fill textarea
    if (this.hasTextareaTarget) {
      this.textareaTarget.value = text
      // Focus textarea so user can edit or press Enter to send
      this.textareaTarget.focus()
    }

    // Clear candidates
    this.clearCandidates()
  }

  /**
   * Handle user input - discard candidates when user starts typing.
   */
  handleInput() {
    if (this.hasTextareaTarget && this.textareaTarget.value.trim().length > 0) {
      this.clearCandidates()
    }
  }

  /**
   * Clear all candidates from the display.
   */
  clearCandidates() {
    if (this.hasCandidatesListTarget) {
      this.candidatesListTarget.innerHTML = ""
    }
    if (this.hasCandidatesContainerTarget) {
      this.candidatesContainerTarget.classList.add("hidden")
    }
  }

  /**
   * Generate with a specific count - called from dropdown menu.
   * Sets the count and immediately triggers generation.
   */
  generateWithCount(event) {
    const count = parseInt(event.currentTarget.dataset.count, 10)
    if (count >= 1 && count <= 4) {
      this.candidateCountValue = count
    }

    // Close dropdown by removing focus from the active element
    document.activeElement?.blur()

    // Trigger generation
    this.generate()
  }

  /**
   * Toggle full copilot mode.
   * Works with both checkbox (legacy) and button (new) toggle styles.
   */
  async toggleFullMode(event) {
    // Prevent rapid clicking race conditions
    if (this.isProcessing) return
    this.isProcessing = true

    // Determine new state - toggle current state
    const wasEnabled = this.fullValue
    const newMode = wasEnabled ? "none" : "full"

    // Update local state immediately for responsive UI
    this.fullValue = !wasEnabled
    this.updateUIForMode()

    // Get the toggle button from event or target
    const toggleBtn = event?.currentTarget || this.fullToggleTarget

    // Update counter to default steps (shown on both enable and disable)
    if (this.hasStepsCounterTarget) {
      const defaultSteps = toggleBtn?.dataset?.copilotDefaultSteps || "4"
      this.stepsCounterTarget.textContent = defaultSteps
    }

    // Persist to server
    try {
      const response = await fetch(this.membershipUpdateUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({
          space_membership: { copilot_mode: newMode }
        })
      })

      if (!response.ok) {
        // Revert state on failure
        this.fullValue = wasEnabled
        this.updateUIForMode()
        this.showToast("Failed to update Copilot mode", "error")
      } else {
        // Parse response to get actual remaining steps from server
        const data = await response.json().catch(() => ({}))
        if (data.copilot_remaining_steps !== undefined && this.hasStepsCounterTarget) {
          this.stepsCounterTarget.textContent = data.copilot_remaining_steps
        }

        // If Auto mode was disabled (mutual exclusivity), update the Auto mode button
        if (data.auto_mode_disabled) {
          this.notifyAutoModeDisabled(data.auto_mode_remaining_rounds || 0)
          this.showToast("Copilot enabled, Auto mode disabled", "success")
        } else {
          // Show success feedback without reload - UI is already updated
          this.showToast(newMode === "full" ? "Copilot enabled" : "Copilot disabled", "success")
        }
      }
    } catch (error) {
      // Revert state on error
      this.fullValue = wasEnabled
      this.updateUIForMode()
      this.showToast("Failed to update Copilot mode", "error")
    } finally {
      this.isProcessing = false
    }
  }

  /**
   * Update UI elements based on full mode state.
   * Note: This does NOT modify stepsCounter - that's handled by server-side rendering
   * and specific methods like disableCopilotDueToStepsExhausted() and toggleFullMode().
   */
  updateUIForMode() {
    const enabled = this.fullValue

    if (this.hasTextareaTarget) {
      this.textareaTarget.disabled = enabled
      // Update placeholder text
      this.textareaTarget.placeholder = enabled
        ? "Copilot is writing for your persona..."
        : "Type your message..."
    }
    if (this.hasGenerateBtnTarget) {
      this.generateBtnTarget.disabled = enabled
    }
    if (this.hasCountBtnTarget) {
      this.countBtnTarget.disabled = enabled
    }
    if (this.hasSendBtnTarget) {
      this.sendBtnTarget.disabled = enabled
    }

    // Update toggle button styling (btn-success when enabled, btn-ghost when disabled)
    if (this.hasFullToggleTarget) {
      const btn = this.fullToggleTarget
      if (enabled) {
        btn.classList.remove("btn-ghost")
        btn.classList.add("btn-success")
      } else {
        btn.classList.remove("btn-success")
        btn.classList.add("btn-ghost")
      }
    }

    // Notify message-form controller about copilot state change
    // This ensures Send button stays correctly disabled when scheduling state changes
    window.dispatchEvent(new CustomEvent("copilot:state-changed", {
      detail: { copilotFull: enabled },
      bubbles: true,
      cancelable: true
    }))
  }

  /**
   * Update generate button state during generation.
   */
  updateGenerateButtonState() {
    if (this.hasGenerateBtnTarget) {
      this.generateBtnTarget.disabled = true
    }
    if (this.hasGenerateIconTarget) {
      this.generateIconTarget.classList.add("hidden")
    }
    if (this.hasGenerateSpinnerTarget) {
      this.generateSpinnerTarget.classList.remove("hidden")
    }
    if (this.hasGenerateTextTarget) {
      this.generateTextTarget.textContent = "Generating..."
    }
    if (this.hasCountBtnTarget) {
      this.countBtnTarget.disabled = true
    }
  }

  /**
   * Reset generate button to normal state.
   */
  resetGenerateButton() {
    this.generatingValue = false

    if (this.hasGenerateBtnTarget) {
      this.generateBtnTarget.disabled = this.fullValue
    }
    if (this.hasGenerateIconTarget) {
      this.generateIconTarget.classList.remove("hidden")
    }
    if (this.hasGenerateSpinnerTarget) {
      this.generateSpinnerTarget.classList.add("hidden")
    }
    if (this.hasGenerateTextTarget) {
      this.generateTextTarget.textContent = "Vibe"
    }
    if (this.hasCountBtnTarget) {
      this.countBtnTarget.disabled = this.fullValue
    }
  }

  /**
   * Get CSRF token from meta tag.
   */
  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  /**
   * Notify Auto mode button that it was disabled due to Copilot being enabled.
   * Dispatches a custom event that the Auto mode toggle controller listens for.
   * @param {number} remainingRounds - The remaining rounds (should be 0)
   */
  notifyAutoModeDisabled(remainingRounds) {
    window.dispatchEvent(new CustomEvent("auto-mode:disabled", {
      detail: { remainingRounds },
      bubbles: true,
      cancelable: true
    }))
  }

  /**
   * Show a toast notification using the global toast:show event.
   * @param {string} message - The message to display
   * @param {string} type - The type: "info", "success", "warning", "error"
   */
  showToast(message, type = "info") {
    window.dispatchEvent(new CustomEvent("toast:show", {
      detail: { message, type, duration: 5000 },
      bubbles: true,
      cancelable: true
    }))
  }
}
