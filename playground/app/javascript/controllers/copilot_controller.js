import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { subscribeToChannel, unsubscribe } from "../chat/cable_subscription"
import { AUTO_MODE_DISABLED_EVENT, USER_TYPING_DISABLE_COPILOT_EVENT, dispatchWindowEvent } from "../chat/events"
import { generateUUID } from "../chat/copilot/uuid"
import { areCandidatesVisible, getCandidateButtons, selectCandidateByIndex, clearCandidates, handleCopilotCandidate, selectCandidate, handleInput, generateWithCount } from "../chat/copilot/candidates"
import { handleKeydown } from "../chat/copilot/keyboard"
import { jsonPatch, jsonRequest, showToast, withRequestLock } from "../request_helpers"

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
    window.addEventListener(USER_TYPING_DISABLE_COPILOT_EVENT, this.handleUserTypingDisable)

    // Sync UI state on connect - important after Turbo Stream replacements
    // The fullValue is read from data-copilot-full-value attribute
    this.updateUIForMode()
  }

  disconnect() {
    this.unsubscribeFromChannel()
    document.removeEventListener("keydown", this.handleKeydown)
    window.removeEventListener(USER_TYPING_DISABLE_COPILOT_EVENT, this.handleUserTypingDisable)
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
      const { response } = await jsonPatch(this.membershipUpdateUrlValue, {
        body: { space_membership: { copilot_mode: "none" } }
      })

      if (response.ok) {
        showToast("Copilot disabled - you are typing", "info", 5000)
      }
      // Silently fail - UI already updated, user is typing
    } catch (error) {
      // Silently fail - UI already updated, user is typing
      logger.warn("Failed to disable copilot:", error)
    }
  }

  /**
   * Handle keyboard shortcuts for candidate selection.
   * - 1-4: Select candidate at index (when not typing)
   * - Escape: Clear candidates (always works when visible)
   */
  handleKeydown(event) {
    handleKeydown(this, event)
  }

  /**
   * Check if candidates container is visible.
   * @returns {boolean}
   */
  areCandidatesVisible() {
    return areCandidatesVisible(this)
  }

  /**
   * Get all candidate buttons.
   * @returns {HTMLElement[]}
   */
  getCandidateButtons() {
    return getCandidateButtons(this)
  }

  /**
   * Select a candidate by index and fill textarea.
   * @param {number} index - 0-based index
   */
  selectCandidateByIndex(index) {
    selectCandidateByIndex(this, index)
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
      logger.warn("CopilotChannel: no membership_id, skipping subscription")
      return
    }

    // Subscribe to the dedicated CopilotChannel (not ConversationChannel)
    // Includes membership_id for per-user unicast streaming
    this.channel = await subscribeToChannel(
      {
        channel: "CopilotChannel",
        space_id: this.spaceId,
        space_membership_id: this.membershipIdValue
      },
      { received: this.handleMessage.bind(this) },
      { label: "CopilotChannel" }
    )
  }

  unsubscribeFromChannel() {
    unsubscribe(this.channel)
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
      const { response, data: error } = await jsonRequest(this.urlValue, {
        method: "POST",
        body: {
          candidate_count: this.candidateCountValue,
          generation_id: this.generationIdValue
        }
      })

      if (!response.ok) {
        logger.error("Generation failed:", error || { status: response.status })
        this.resetGenerateButton()
      }
      // Success: wait for ActionCable events
    } catch (error) {
      logger.error("Generation request failed:", error)
      this.resetGenerateButton()
    }
  }

  /**
   * Handle incoming candidate from ActionCable.
   */
  handleCopilotCandidate(data) {
    handleCopilotCandidate(this, data)
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
    logger.error("Copilot generation error:", data.error)
    this.resetGenerateButton()
    showToast(`Generation failed: ${data.error}`, "error", 5000)
  }

  /**
   * Handle full copilot mode disabled (error or exhaustion).
   * Updates UI without page reload for seamless experience.
   */
  handleCopilotDisabled(data) {
    const error = data?.error
    const reason = data?.reason

    logger.warn("Copilot mode disabled:", { error, reason })

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

    showToast(message, type, 5000)
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
    selectCandidate(this, event)
  }

  /**
   * Handle user input - discard candidates when user starts typing.
   */
  handleInput() {
    handleInput(this)
  }

  /**
   * Clear all candidates from the display.
   */
  clearCandidates() {
    clearCandidates(this)
  }

  /**
   * Generate with a specific count - called from dropdown menu.
   * Sets the count and immediately triggers generation.
   */
  generateWithCount(event) {
    generateWithCount(this, event)
  }

  /**
   * Toggle full copilot mode.
   */
  async toggleFullMode(event) {
    await withRequestLock(this.membershipUpdateUrlValue, async () => {
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
        const { response, data } = await jsonPatch(this.membershipUpdateUrlValue, {
          body: { space_membership: { copilot_mode: newMode } }
        })

        if (!response.ok) {
          // Revert state on failure
          this.fullValue = wasEnabled
          this.updateUIForMode()
          showToast("Failed to update Copilot mode", "error", 5000)
          return
        }

        // Parse response to get actual remaining steps from server
        const payload = data || {}
        if (payload.copilot_remaining_steps !== undefined && this.hasStepsCounterTarget) {
          this.stepsCounterTarget.textContent = payload.copilot_remaining_steps
        }

        // If Auto mode was disabled (mutual exclusivity), update the Auto mode button
        if (payload.auto_mode_disabled) {
          this.notifyAutoModeDisabled(payload.auto_mode_remaining_rounds || 0)
          showToast("Copilot enabled, Auto mode disabled", "success", 5000)
          return
        }

        // Show success feedback without reload - UI is already updated
        showToast(newMode === "full" ? "Copilot enabled" : "Copilot disabled", "success", 5000)
      } catch (error) {
        // Revert state on error
        logger.error("Copilot mode update failed:", error)
        this.fullValue = wasEnabled
        this.updateUIForMode()
        showToast("Failed to update Copilot mode", "error", 5000)
      }
    })
  }

  /**
   * Update UI elements based on full mode state.
   *
   * Copilot mode is a "soft lock" - user can still type to auto-disable it.
   * Only the Vibe button is disabled (no need for manual suggestions when Copilot is active).
   *
   * Note: This does NOT modify stepsCounter - that's handled by server-side rendering
   * and specific methods like disableCopilotDueToStepsExhausted() and toggleFullMode().
   */
  updateUIForMode() {
    const enabled = this.fullValue

    // Update placeholder text (but don't disable textarea - user can type to disable Copilot)
    if (this.hasTextareaTarget) {
      this.textareaTarget.placeholder = enabled
        ? "Copilot is active. Type here to take over..."
        : "Type your message..."
    }

    // Disable Vibe button when Copilot is active (no need for manual suggestions)
    if (this.hasGenerateBtnTarget) {
      this.generateBtnTarget.disabled = enabled
    }
    if (this.hasCountBtnTarget) {
      this.countBtnTarget.disabled = enabled
    }

    // Note: textarea and sendBtn are NOT disabled - user can type to auto-disable Copilot
    // See: docs/spec/SILLYTAVERN_DIVERGENCES.md "User input always takes priority"

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
   * Notify Auto mode button that it was disabled due to Copilot being enabled.
   * Dispatches a custom event that the Auto mode toggle controller listens for.
   * @param {number} remainingRounds - The remaining rounds (should be 0)
   */
  notifyAutoModeDisabled(remainingRounds) {
    dispatchWindowEvent(AUTO_MODE_DISABLED_EVENT, { remainingRounds }, { cancelable: true })
  }

}
