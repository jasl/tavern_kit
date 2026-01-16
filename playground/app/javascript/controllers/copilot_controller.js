import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { USER_TYPING_DISABLE_COPILOT_EVENT } from "../chat/events"
import { areCandidatesVisible, getCandidateButtons, selectCandidateByIndex, clearCandidates, handleCopilotCandidate, selectCandidate, handleInput, generateWithCount } from "../chat/copilot/candidates"
import { handleKeydown } from "../chat/copilot/keyboard"
import { subscribeToCopilotChannel, unsubscribeFromCopilotChannel } from "../chat/copilot/subscription"
import { generate, updateGenerateButtonState, resetGenerateButton } from "../chat/copilot/generation"
import { handleUserTypingDisable, disableCopilotDueToUserTyping, handleCopilotDisabled, handleCopilotStepsUpdated, toggleFullMode, updateUIForMode, notifyAutoModeDisabled } from "../chat/copilot/mode"

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
    "loadingIndicator",
    "errorIndicator",
    "errorMessage",
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
    handleUserTypingDisable(this)
  }

  /**
   * Disable Copilot mode because user started typing.
   * Similar to toggleFullMode but with specific messaging.
   */
  async disableCopilotDueToUserTyping() {
    await disableCopilotDueToUserTyping(this)
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
    await subscribeToCopilotChannel(this)
  }

  unsubscribeFromChannel() {
    unsubscribeFromCopilotChannel(this)
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
    await generate(this)
  }

  /**
   * Handle incoming candidate from ActionCable.
   */
  handleCopilotCandidate(data) {
    handleCopilotCandidate(this, data)
  }

  /**
   * Handle generation error from ActionCable.
   */
  handleCopilotError(data) {
    if (data.generation_id !== this.generationIdValue) return
    logger.error("Copilot generation error:", data.error)
    this.showErrorIndicator(data.error || "Generation failed")
    this.resetGenerateButton()
  }

  /**
   * Handle full copilot mode disabled (error or exhaustion).
   * Updates UI without page reload for seamless experience.
   */
  handleCopilotDisabled(data) {
    handleCopilotDisabled(this, data)
  }

  /**
   * Handle copilot steps updated from ActionCable.
   * Updates the displayed remaining steps count.
   */
  handleCopilotStepsUpdated(data) {
    handleCopilotStepsUpdated(this, data)
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
    await toggleFullMode(this, event)
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
    updateUIForMode(this)
  }

  /**
   * Update generate button state during generation.
   */
  updateGenerateButtonState() {
    updateGenerateButtonState(this)
  }

  /**
   * Reset generate button to normal state.
   */
  resetGenerateButton() {
    resetGenerateButton(this)
  }

  /**
   * Notify Auto mode button that it was disabled due to Copilot being enabled.
   * Dispatches a custom event that the Auto mode toggle controller listens for.
   * @param {number} remainingRounds - The remaining rounds (should be 0)
   */
  notifyAutoModeDisabled(remainingRounds) {
    notifyAutoModeDisabled(remainingRounds)
  }

  /**
   * Retry generation after an error.
   * Clears the error state and triggers a new generation.
   */
  retryGenerate() {
    this.hideErrorIndicator()
    this.generate()
  }

  /**
   * Show loading indicator in candidates area.
   */
  showLoadingIndicator() {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.remove("hidden")
    }
    if (this.hasErrorIndicatorTarget) {
      this.errorIndicatorTarget.classList.add("hidden")
    }
  }

  /**
   * Hide loading indicator.
   */
  hideLoadingIndicator() {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.add("hidden")
    }
  }

  /**
   * Show error indicator with message.
   * @param {string} message - Error message to display
   */
  showErrorIndicator(message) {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.add("hidden")
    }
    if (this.hasErrorIndicatorTarget) {
      this.errorIndicatorTarget.classList.remove("hidden")
    }
    if (this.hasErrorMessageTarget && message) {
      this.errorMessageTarget.textContent = message
    }
  }

  /**
   * Hide error indicator.
   */
  hideErrorIndicator() {
    if (this.hasErrorIndicatorTarget) {
      this.errorIndicatorTarget.classList.add("hidden")
    }
  }

}
