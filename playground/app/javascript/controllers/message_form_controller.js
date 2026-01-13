import { Controller } from "@hotwired/stimulus"
import { getCableConnected } from "../conversation_state"
import { CABLE_CONNECTED_EVENT, CABLE_DISCONNECTED_EVENT, SCHEDULING_STATE_CHANGED_EVENT, USER_TYPING_DISABLE_AUTO_MODE_EVENT, USER_TYPING_DISABLE_COPILOT_EVENT, dispatchWindowEvent } from "../chat/events"
import { showToast } from "../request_helpers"

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
  static targets = ["textarea", "sendBtn", "cableDisconnectAlert"]
  static values = {
    conversationId: Number,
    rejectPolicy: { type: Boolean, default: false },
    schedulingState: { type: String, default: "idle" },
    spaceReadOnly: { type: Boolean, default: false },
    cableConnected: { type: Boolean, default: true }
  }

  connect() {
    // Listen for turbo:submit-end on the form element
    this.handleSubmitEnd = this.handleSubmitEnd.bind(this)
    this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd)

    // Listen for scheduling state changes from ActionCable
    this.handleSchedulingStateChanged = this.handleSchedulingStateChanged.bind(this)
    window.addEventListener(SCHEDULING_STATE_CHANGED_EVENT, this.handleSchedulingStateChanged)

    // Listen for ActionCable connection state changes
    this.handleCableConnected = this.handleCableConnected.bind(this)
    this.handleCableDisconnected = this.handleCableDisconnected.bind(this)
    window.addEventListener(CABLE_CONNECTED_EVENT, this.handleCableConnected)
    window.addEventListener(CABLE_DISCONNECTED_EVENT, this.handleCableDisconnected)

    // If this controller is Turbo Stream-replaced while cable is disconnected,
    // it won't receive the historical cable:disconnected event. Sync from
    // the global connection state to keep the banner/disabled state correct.
    this.syncCableConnectedFromGlobalState()

    // Apply initial lock state
    this.updateLockedState()
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
    window.removeEventListener(SCHEDULING_STATE_CHANGED_EVENT, this.handleSchedulingStateChanged)
    window.removeEventListener(CABLE_CONNECTED_EVENT, this.handleCableConnected)
    window.removeEventListener(CABLE_DISCONNECTED_EVENT, this.handleCableDisconnected)
  }

  /**
   * Called when cableConnectedValue changes (Stimulus value callback).
   */
  cableConnectedValueChanged() {
    this.updateLockedState()
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
    if (!this.matchesConversationEvent(event)) return

    if (event.detail?.schedulingState) {
      this.schedulingStateValue = event.detail.schedulingState
    }
  }

  handleCableConnected(event) {
    if (!this.matchesConversationEvent(event)) return
    this.cableConnectedValue = true
  }

  handleCableDisconnected(event) {
    if (!this.matchesConversationEvent(event)) return
    this.cableConnectedValue = false
  }

  matchesConversationEvent(event) {
    const eventConversationId = Number(event?.detail?.conversationId)
    if (!eventConversationId) return true
    if (!this.hasConversationIdValue) return true
    return this.conversationIdValue === eventConversationId
  }

  syncCableConnectedFromGlobalState() {
    if (!this.hasConversationIdValue) return

    const connected = getCableConnected(this.conversationIdValue)
    if (connected === false) {
      this.cableConnectedValue = false
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
    const shouldDisableTextarea = this.spaceReadOnlyValue || isGenerationLocked
    const shouldDisableSendBtn = shouldDisableTextarea || this.cableConnectedValue === false

    if (this.hasTextareaTarget) {
      this.textareaTarget.disabled = shouldDisableTextarea

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
      this.sendBtnTarget.disabled = shouldDisableSendBtn
    }

    if (this.hasCableDisconnectAlertTarget) {
      this.cableDisconnectAlertTarget.classList.toggle("hidden", this.cableConnectedValue !== false)
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
      if (this.cableConnectedValue === false) {
        event.preventDefault()
        showToast("Disconnected. Reconnecting…", "warning")
        return
      }

      event.preventDefault()

      // Find and submit the form
      const form = this.element.closest("form") || this.element.querySelector("form")
      if (form) {
        // Use requestSubmit to trigger validation and submit events
        form.requestSubmit()
      }
    }
  }

  reloadPage() {
    window.location.reload()
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
      const fetchResponse = event.detail?.fetchResponse
      const toastAlreadyShown = fetchResponse?.header?.("X-TavernKit-Toast") === "1"
      if (toastAlreadyShown) return

      // Use Turbo's statusCode getter for reliable status retrieval
      const status = fetchResponse?.statusCode

      if (status === 423) {
        showToast("AI is generating a response. Please wait…", "warning")
      } else if (status === 409) {
        showToast("Message not sent due to a conflict. Please try again.", "warning")
      } else {
        showToast("Message not sent. Please try again.", "error")
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
    dispatchWindowEvent(USER_TYPING_DISABLE_COPILOT_EVENT, null, { cancelable: true })
    dispatchWindowEvent(USER_TYPING_DISABLE_AUTO_MODE_EVENT, null, { cancelable: true })
  }

}
