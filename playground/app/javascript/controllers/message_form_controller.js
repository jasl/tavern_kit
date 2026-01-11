import { Controller } from "@hotwired/stimulus"

/**
 * Message form controller for handling message input interactions.
 *
 * Provides keyboard shortcuts for submitting messages:
 * - Enter (without modifiers): Submit the form
 * - Shift+Enter: Insert newline (default browser behavior)
 *
 * Also handles:
 * - Clearing textarea after successful submission
 * - Error toast notifications for submission failures
 * - Dynamic input locking based on scheduling state (reject policy)
 *
 * ## Input Locking (ST/RisuAI-aligned behavior)
 *
 * When `rejectPolicyValue` is true and `schedulingStateValue` is "ai_generating",
 * the textarea and send button are disabled. This prevents users from sending
 * messages while AI is generating a response.
 *
 * The locking state is updated dynamically via the `scheduling:state-changed`
 * window event, dispatched by conversation_channel_controller when the
 * `conversation_queue_updated` ActionCable message is received.
 *
 * @example HTML structure
 *   <div data-controller="message-form"
 *        data-message-form-reject-policy-value="true"
 *        data-message-form-scheduling-state-value="idle">
 *     <form>
 *       <textarea data-action="keydown->message-form#handleKeydown"
 *                 data-message-form-target="textarea"></textarea>
 *       <button type="submit" data-message-form-target="sendBtn">Send</button>
 *     </form>
 *   </div>
 */
export default class extends Controller {
  static targets = ["textarea", "sendBtn"]
  static values = {
    rejectPolicy: { type: Boolean, default: false },
    schedulingState: { type: String, default: "idle" },
    spaceReadOnly: { type: Boolean, default: false }
  }

  connect() {
    // Listen for turbo:submit-end on the form element
    this.handleSubmitEnd = this.handleSubmitEnd.bind(this)
    this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd)

    // Listen for scheduling state changes from ActionCable
    this.handleSchedulingStateChanged = this.handleSchedulingStateChanged.bind(this)
    window.addEventListener("scheduling:state-changed", this.handleSchedulingStateChanged)

    // Apply initial lock state
    this.updateLockedState()
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
    window.removeEventListener("scheduling:state-changed", this.handleSchedulingStateChanged)
  }

  /**
   * Called when schedulingStateValue changes (Stimulus value callback).
   */
  schedulingStateValueChanged() {
    this.updateLockedState()
  }

  /**
   * Called when rejectPolicyValue changes (Stimulus value callback).
   */
  rejectPolicyValueChanged() {
    this.updateLockedState()
  }

  /**
   * Handle scheduling state change event from ActionCable.
   *
   * @param {CustomEvent} event - Event with detail.schedulingState
   */
  handleSchedulingStateChanged(event) {
    if (event.detail?.schedulingState) {
      this.schedulingStateValue = event.detail.schedulingState
    }
  }

  /**
   * Update the locked state of textarea and send button.
   *
   * Hard locked when:
   * - Space is read-only, OR
   * - Reject policy is enabled AND AI is generating
   *
   * Note: Copilot/Auto mode are "soft locks" - user can type to auto-disable them.
   * See: docs/spec/SILLYTAVERN_DIVERGENCES.md "User input always takes priority"
   */
  updateLockedState() {
    const isGenerationLocked = this.rejectPolicyValue && this.schedulingStateValue === "ai_generating"
    const shouldDisable = this.spaceReadOnlyValue || isGenerationLocked

    if (this.hasTextareaTarget) {
      this.textareaTarget.disabled = shouldDisable

      // Update placeholder based on lock reason
      if (isGenerationLocked) {
        const lockedPlaceholder = this.textareaTarget.dataset.lockedPlaceholder
        if (lockedPlaceholder) {
          this.textareaTarget.placeholder = lockedPlaceholder
        }
      } else {
        const defaultPlaceholder = this.textareaTarget.dataset.defaultPlaceholder
        if (defaultPlaceholder) {
          this.textareaTarget.placeholder = defaultPlaceholder
        }
      }
    }

    if (this.hasSendBtnTarget) {
      this.sendBtnTarget.disabled = shouldDisable
    }
  }

  /**
   * Handle keydown events on the textarea.
   *
   * Submits the form when Enter is pressed without Shift.
   * Shift+Enter allows inserting newlines.
   */
  handleKeydown(event) {
    // Submit on Enter (without Shift, Ctrl, Alt, or Meta)
    if (event.key === "Enter" && !event.shiftKey && !event.ctrlKey && !event.altKey && !event.metaKey) {
      event.preventDefault()

      // Find and submit the form
      const form = this.element.closest("form") || this.element.querySelector("form")
      if (form) {
        // Use requestSubmit to trigger validation and submit events
        form.requestSubmit()
      }
    }
  }

  /**
   * Handle form submission end - clear textarea on success, show toast on error.
   * Turbo emits turbo:submit-end after the form submission completes.
   *
   * Handles specific status codes:
   * - 423 Locked: AI is generating (during_generation_user_input_policy == "reject")
   * - 409 Conflict: Message conflict
   * - Other errors: Generic error message
   */
  handleSubmitEnd(event) {
    const textarea = this.hasTextareaTarget
      ? this.textareaTarget
      : this.element.querySelector("textarea")

    if (!event.detail?.success) {
      // Use Turbo's statusCode getter for reliable status retrieval
      const status = event.detail?.fetchResponse?.statusCode

      if (status === 423) {
        this.showToast("AI is generating a response. Please wait…", "warning")
      } else if (status === 409) {
        this.showToast("Message not sent due to a conflict. Please try again.", "warning")
      } else {
        this.showToast("Message not sent. Please try again.", "error")
      }

      return
    }

    if (event.detail?.fetchResponse && textarea) {
      textarea.value = ""
    }
  }

  /**
   * Handle user input - dispatch events to disable Copilot and Auto mode.
   *
   * When user starts typing, we want to:
   * 1. Disable Copilot mode (prevent AI from speaking as user)
   * 2. Disable Auto mode (prevent AI-to-AI continuation)
   *
   * This prevents race conditions where both user and AI messages are sent.
   * The actual cancellation of queued runs happens on submit (backend).
   */
  handleInput(event) {
    // Only dispatch if there's actual content being typed
    if (!event.target.value.trim()) return

    // Dispatch events for other controllers to handle
    // Using window-level events for cross-controller communication
    window.dispatchEvent(new CustomEvent("user:typing:disable-copilot", {
      bubbles: true,
      cancelable: true
    }))

    window.dispatchEvent(new CustomEvent("user:typing:disable-auto-mode", {
      bubbles: true,
      cancelable: true
    }))
  }

  /**
   * Show a toast notification using the global toast:show event.
   */
  showToast(message, type = "info") {
    window.dispatchEvent(new CustomEvent("toast:show", {
      detail: { message, type, duration: 3000 },
      bubbles: true,
      cancelable: true
    }))
  }
}
