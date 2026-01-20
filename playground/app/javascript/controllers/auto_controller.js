import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { USER_TYPING_DISABLE_AUTO_EVENT } from "../chat/events"
import { areCandidatesVisible, getCandidateButtons, selectCandidateByIndex, clearCandidates, handleAutoCandidate, selectCandidate, handleInput, generateWithCount } from "../chat/auto/candidates"
import { handleKeydown } from "../chat/auto/keyboard"
import { subscribeToAutoChannel, unsubscribeFromAutoChannel } from "../chat/auto/subscription"
import { generate, updateGenerateButtonState, resetGenerateButton } from "../chat/auto/generation"
import { handleUserTypingDisable, disableAutoDueToUserTyping, handleAutoDisabled, handleAutoStepsUpdated, toggleAutoMode, updateUIForMode, notifyAutoWithoutHumanDisabled } from "../chat/auto/mode"

/**
 * Auto Controller
 *
 * Manages suggestion generation and Auto toggle for users.
 * Handles:
 * - Generating suggestion candidates via POST request
 * - Receiving candidates via ActionCable
 * - Displaying candidates as clickable buttons
 * - Sending selected candidates
 * - Toggling Auto on/off
 *
 * @example HTML structure
 *   <div data-controller="auto"
 *        data-auto-url-value="/playgrounds/123/auto_candidates"
 *        data-auto-auto-value="false"
 *        data-auto-membership-id-value="456"
 *        data-auto-membership-update-url-value="/playgrounds/123/memberships/456">
 *     <div data-auto-target="candidatesContainer" class="hidden">
 *       <div data-auto-target="candidatesList"></div>
 *     </div>
 *     <form data-auto-target="form">
 *       <textarea data-auto-target="textarea"></textarea>
 *     </form>
 *     <button data-auto-target="generateBtn" data-action="auto#generate">Generate</button>
 *     <input type="checkbox" data-auto-target="autoToggle" data-action="change->auto#toggleAutoMode">
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
    "autoToggle",
    "stepsCounter"
  ]

  static values = {
    url: String,
    auto: Boolean,
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
    window.addEventListener(USER_TYPING_DISABLE_AUTO_EVENT, this.handleUserTypingDisable)

    // Sync UI state on connect - important after Turbo Stream replacements
    // The autoValue is read from data-auto-auto-value attribute
    this.updateUIForMode()
  }

  disconnect() {
    this.unsubscribeFromChannel()
    document.removeEventListener("keydown", this.handleKeydown)
    window.removeEventListener(USER_TYPING_DISABLE_AUTO_EVENT, this.handleUserTypingDisable)
  }

  /**
   * Handle user typing event - disable Auto when user starts typing.
   * This prevents race conditions where both user and AI messages are sent.
   */
  handleUserTypingDisable() {
    handleUserTypingDisable(this)
  }

  /**
   * Disable Auto because user started typing.
   * Similar to toggleAutoMode but with specific messaging.
   */
  async disableAutoDueToUserTyping() {
    await disableAutoDueToUserTyping(this)
  }

  handleKeydown(event) {
    handleKeydown(this, event)
  }

  areCandidatesVisible() {
    return areCandidatesVisible(this)
  }

  getCandidateButtons() {
    return getCandidateButtons(this)
  }

  selectCandidateByIndex(index) {
    selectCandidateByIndex(this, index)
  }

  /**
   * Subscribe to AutoChannel for membership-scoped events.
   */
  async subscribeToChannel() {
    await subscribeToAutoChannel(this)
  }

  unsubscribeFromChannel() {
    unsubscribeFromAutoChannel(this)
  }

  handleMessage(data) {
    if (!data || !data.type) return

    switch (data.type) {
      case "auto_candidate":
        this.handleAutoCandidate(data)
        break
      case "auto_candidate_error":
        this.handleAutoCandidateError(data)
        break
      case "auto_disabled":
        this.handleAutoDisabled(data)
        break
      case "auto_steps_updated":
        this.handleAutoStepsUpdated(data)
        break
    }
  }

  async generate() {
    await generate(this)
  }

  handleAutoCandidate(data) {
    handleAutoCandidate(this, data)
  }

  handleAutoCandidateError(data) {
    if (data.generation_id !== this.generationIdValue) return
    logger.error("Suggestion generation error:", data.error)
    this.showErrorIndicator(data.error || "Generation failed")
    this.resetGenerateButton()
  }

  handleAutoDisabled(data) {
    handleAutoDisabled(this, data)
  }

  handleAutoStepsUpdated(data) {
    handleAutoStepsUpdated(this, data)
  }

  selectCandidate(event) {
    selectCandidate(this, event)
  }

  handleInput() {
    handleInput(this)
  }

  clearCandidates() {
    clearCandidates(this)
  }

  generateWithCount(event) {
    generateWithCount(this, event)
  }

  async toggleAutoMode(event) {
    await toggleAutoMode(this, event)
  }

  updateUIForMode() {
    updateUIForMode(this)
  }

  updateGenerateButtonState() {
    updateGenerateButtonState(this)
  }

  resetGenerateButton() {
    resetGenerateButton(this)
  }

  notifyAutoWithoutHumanDisabled(remainingRounds) {
    notifyAutoWithoutHumanDisabled(remainingRounds)
  }

  retryGenerate() {
    this.hideErrorIndicator()
    this.generate()
  }

  showLoadingIndicator() {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.remove("hidden")
    }
    if (this.hasErrorIndicatorTarget) {
      this.errorIndicatorTarget.classList.add("hidden")
    }
  }

  hideLoadingIndicator() {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.add("hidden")
    }
  }

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

  hideErrorIndicator() {
    if (this.hasErrorIndicatorTarget) {
      this.errorIndicatorTarget.classList.add("hidden")
    }
  }
}
