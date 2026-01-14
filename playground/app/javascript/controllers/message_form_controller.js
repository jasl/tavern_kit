import { Controller } from "@hotwired/stimulus"
import { bindMessageFormEvents } from "../chat/message_form/bindings"
import { updateLockedState } from "../chat/message_form/lock_state"
import { handleKeydown } from "../chat/message_form/submit"
import { handleInput } from "../chat/message_form/typing"

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
    this.disconnectEvents = bindMessageFormEvents(this)
  }

  disconnect() {
    this.disconnectEvents?.()
  }

  /**
   * Called when cableConnectedValue changes (Stimulus value callback).
   */
  cableConnectedValueChanged() {
    updateLockedState(this)
  }

  /**
   * Called when schedulingStateValue changes (Stimulus value callback).
   */
  schedulingStateValueChanged() {
    updateLockedState(this)
  }

  /**
   * Called when rejectPolicyValue changes (Stimulus value callback).
   */
  rejectPolicyValueChanged() {
    updateLockedState(this)
  }

  /**
   * Handle keydown events on the textarea.
   *
   * Submits the form when Enter is pressed without Shift.
   * Shift+Enter allows inserting newlines.
   */
  handleKeydown(event) {
    handleKeydown(this, event)
  }

  reloadPage() {
    window.location.reload()
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
    handleInput(this, event)
  }

}
