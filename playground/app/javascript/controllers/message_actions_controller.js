import { Controller } from "@hotwired/stimulus"
import { findMessagesList } from "../chat/dom"
import { registerListObserver, unregisterListObserver } from "../chat/message_actions/list_registry"
import { findCurrentMembershipId, findTailMessageId, domTailMessageId, setTailMessageId, syncTailMessageIdIfIAmTail, isTailMessage } from "../chat/message_actions/tail"
import { copy, regenerate, triggerBranch, showDebug } from "../chat/message_actions/actions"
import { handleEditKeydown, cancelEdit, handleEscape } from "../chat/message_actions/edit"
import { getMessageContent } from "../chat/message_actions/content"

/**
 * Message Actions Controller
 *
 * Handles message action buttons: edit, delete, regenerate, copy.
 * Provides enhanced UX with inline editing and toast confirmations.
 *
 * Also controls button visibility based on:
 * - Message ownership (current user's membership)
 * - Message position (tail message only for edit/delete)
 * - Message role (assistant for swipe, user for edit/delete)
 *
 * This client-side logic matches backend constraints and works correctly
 * even when messages are rendered via Turbo broadcast without current_user context.
 *
 * Tail-only mutation invariant: Any operation that modifies existing timeline
 * content (edit, delete, regenerate, switch swipes) can only be performed on
 * the tail (last) message. To modify earlier messages, use "Branch from here".
 *
 * @example HTML structure
 *   <div data-controller="message-actions"
 *        data-message-actions-message-id-value="123"
 *        data-message-role="user"
 *        data-message-participant-id="456">
 *     <button data-message-actions-target="editButton">Edit</button>
 *     <button data-message-actions-target="deleteButton">Delete</button>
 *     <button data-message-actions-target="branchCta">Branch to edit</button>
 *     <button data-action="click->message-actions#copy">Copy</button>
 *   </div>
 */
export default class extends Controller {
  static targets = ["content", "textarea", "actions", "editButton", "deleteButton", "swipeNav", "regenerateButton", "branchCta", "branchBtn"]
  static values = {
    messageId: Number,
    editing: { type: Boolean, default: false },
    deleting: { type: Boolean, default: false }
  }

  connect() {
    // Bind escape key handler for edit mode
    this.handleEscape = this.handleEscape.bind(this)

    // Get current membership ID from ancestor container
    this.currentMembershipId = findCurrentMembershipId(this)

    // Keep the container's data-tail-message-id in sync when Turbo appends messages.
    // Turbo broadcasts append the new message element, but do not update container attributes.
    // We correct it on connect for the tail message to prevent stale tail detection.
    syncTailMessageIdIfIAmTail(this)

    // Apply visibility rules
    this.updateButtonVisibility()

    // Watch for changes to the messages list (for Turbo broadcasts adding/removing messages).
    // One MutationObserver per list (shared across all message-actions instances) to avoid O(N) observers.
    this.registerListObserver()
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleEscape)
    this.unregisterListObserver()
  }

  /**
   * Find the current membership ID from an ancestor container.
   * This is set on the messages list container and persists across Turbo broadcasts.
   *
   * @returns {string|null} The current membership ID or null if not found
   */
  findCurrentMembershipId() {
    return findCurrentMembershipId(this)
  }

  /**
   * Find the tail message ID from the messages list container.
   * This is set on the container and updated when messages change.
   *
   * @returns {string|null} The tail message ID or null if not found
   */
  findTailMessageId() {
    return findTailMessageId(this)
  }

  /**
   * Find the messages list container element.
   *
   * @returns {HTMLElement|null} The messages list container
   */
  messagesList() {
    return findMessagesList(this.element)
  }

  registerListObserver() {
    registerListObserver(this, this.messagesList())
  }

  unregisterListObserver() {
    unregisterListObserver(this)
  }

  /**
   * Get the tail message ID from the DOM (O(1)) by reading the list's last element child.
   *
   * @param {HTMLElement|null} list - The messages list element
   * @returns {string|null} The tail message ID, or null if not available
   */
  domTailMessageId(list) {
    return domTailMessageId(list)
  }

  /**
   * Set the tail message ID on the messages list container (only if changed).
   *
   * @param {HTMLElement|null} list - The messages list element
   * @param {string|number|null} tailMessageId - The tail message ID
   */
  setTailMessageId(list, tailMessageId) {
    setTailMessageId(list, tailMessageId)
  }

  /**
   * If this message is currently the last element in the list, sync the container's tail ID.
   * This fixes stale data-tail-message-id when Turbo broadcasts append messages.
   */
  syncTailMessageIdIfIAmTail() {
    syncTailMessageIdIfIAmTail(this)
  }

  /**
   * Check if this message is the tail (last) message in the conversation.
   * Uses the explicit tail message ID from DOM attribute for reliability.
   * Falls back to DOM position if attribute is not set.
   *
   * @returns {boolean} True if this is the last message in the list
   */
  isTailMessage() {
    return isTailMessage(this)
  }

  /**
   * Update the visibility of action buttons based on ownership and position.
   *
   * Rules:
   * - Edit/Delete: only visible for current user's tail user messages
   * - Branch CTA: shown for non-tail user messages owned by current user
   * - Swipe navigation: only visible for tail assistant messages (swipeable check in HTML)
   * - Regenerate button: always visible for assistant, tooltip changes for non-tail
   */
  updateButtonVisibility() {
    const participantId = this.element.dataset.messageParticipantId
    const role = this.element.dataset.messageRole
    const isOwner = participantId && this.currentMembershipId && participantId === this.currentMembershipId
    const isTail = this.isTailMessage()

    // Edit/Delete: only for owner's tail user messages
    // Note: Backend also restricts this, but we hide the buttons for better UX
    const canEditDelete = isOwner && isTail && role === "user"

    if (this.hasEditButtonTarget) {
      this.editButtonTarget.classList.toggle("hidden", !canEditDelete)
    }
    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.classList.toggle("hidden", !canEditDelete)
    }

    // Branch CTA: shown for non-tail user messages owned by current user
    // This provides a clear action path instead of just hiding edit/delete
    const showBranchCta = isOwner && !isTail && role === "user"

    if (this.hasBranchCtaTarget) {
      this.branchCtaTarget.classList.toggle("hidden", !showBranchCta)
    }

    // Swipe navigation: only for tail assistant messages
    // The swipeable? check is already done in HTML (the container only renders if swipes exist)
    const canSwipe = isTail && role === "assistant"

    if (this.hasSwipeNavTarget) {
      this.swipeNavTarget.classList.toggle("hidden", !canSwipe)
    }

    // Regenerate button: update tooltip for non-tail messages
    // Non-tail regeneration will auto-branch to preserve timeline consistency
    if (this.hasRegenerateButtonTarget) {
      if (isTail) {
        this.regenerateButtonTarget.title = "Regenerate"
      } else {
        this.regenerateButtonTarget.title = "Regenerate (creates branch)"
      }
    }
  }

  /**
   * Copy message content to clipboard.
   */
  async copy(event) {
    await copy(this, event)
  }

  /**
   * Handle keyboard shortcuts in edit mode.
   */
  handleEditKeydown(event) {
    handleEditKeydown(this, event)
  }

  /**
   * Cancel inline editing.
   */
  cancelEdit() {
    cancelEdit(this)
  }

  /**
   * Handle escape key press.
   */
  handleEscape(event) {
    handleEscape(this, event)
  }

  /**
   * Confirm delete with custom dialog.
   */
  confirmDelete(_event) {
    // The default Turbo confirm is fine for now
    // This method can be enhanced for custom confirmation UI
  }

  /**
   * Show regenerating state on button.
   */
  regenerate(event) {
    regenerate(this, event)
  }

  /**
   * Trigger the branch action from the Branch CTA button.
   * Programmatically clicks the regular branch button to reuse its form submission.
   */
  triggerBranch(event) {
    triggerBranch(this, event)
  }

  /**
   * Show debug info for this message by opening the run detail modal.
   * The run data is stored in the data-run-data attribute of the clicked button.
   */
  showDebug(event) {
    showDebug(this, event)
  }

  /**
   * Get the message content text.
   */
  getMessageContent() {
    return getMessageContent(this)
  }

}
