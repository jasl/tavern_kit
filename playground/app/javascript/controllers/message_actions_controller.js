import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { showToast } from "../request_helpers"
import { copyTextToClipboard } from "../dom_helpers"

const MESSAGE_LIST_REGISTRY = new WeakMap()
const MESSAGE_LIST_UPDATE_DEBOUNCE_MS = 50

function scheduleListUpdate(registry) {
  if (registry.updateTimeout) clearTimeout(registry.updateTimeout)

  registry.updateTimeout = setTimeout(() => {
    registry.updateTimeout = null

    for (const controller of registry.controllers) {
      if (!controller.element?.isConnected) continue
      controller.updateButtonVisibility()
    }
  }, MESSAGE_LIST_UPDATE_DEBOUNCE_MS)
}

function getMessageListRegistry(list) {
  const existing = MESSAGE_LIST_REGISTRY.get(list)
  if (existing) return existing

  const registry = {
    controllers: new Set(),
    updateTimeout: null,
    observer: null
  }

  registry.observer = new MutationObserver((mutations) => {
    const hasChildChanges = mutations.some((mutation) => {
      return mutation.type === "childList" && (mutation.addedNodes.length > 0 || mutation.removedNodes.length > 0)
    })

    const hasAttrChanges = mutations.some((mutation) => {
      return mutation.type === "attributes" && mutation.attributeName === "data-tail-message-id"
    })

    if (!hasChildChanges && !hasAttrChanges) return

    scheduleListUpdate(registry)
  })

  registry.observer.observe(list, {
    childList: true,
    subtree: false,
    attributes: true,
    attributeFilter: ["data-tail-message-id"]
  })

  MESSAGE_LIST_REGISTRY.set(list, registry)
  return registry
}

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
    this.currentMembershipId = this.findCurrentMembershipId()

    // Keep the container's data-tail-message-id in sync when Turbo appends messages.
    // Turbo broadcasts append the new message element, but do not update container attributes.
    // We correct it on connect for the tail message to prevent stale tail detection.
    this.syncTailMessageIdIfIAmTail()

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
    const container = this.element.closest("[data-current-membership-id]")
    return container?.dataset.currentMembershipId || null
  }

  /**
   * Find the tail message ID from the messages list container.
   * This is set on the container and updated when messages change.
   *
   * @returns {string|null} The tail message ID or null if not found
   */
  findTailMessageId() {
    const container = this.element.closest("[data-tail-message-id]")
    return container?.dataset.tailMessageId || null
  }

  /**
   * Find the messages list container element.
   *
   * @returns {HTMLElement|null} The messages list container
   */
  messagesList() {
    return this.element.closest("[data-chat-scroll-target='list']")
  }

  registerListObserver() {
    const list = this.messagesList()
    if (!list) return

    this.messageList = list
    this.messageListRegistry = getMessageListRegistry(list)
    this.messageListRegistry.controllers.add(this)
  }

  unregisterListObserver() {
    if (!this.messageListRegistry || !this.messageList) return

    this.messageListRegistry.controllers.delete(this)

    if (this.messageListRegistry.controllers.size === 0) {
      this.messageListRegistry.observer?.disconnect()
      if (this.messageListRegistry.updateTimeout) clearTimeout(this.messageListRegistry.updateTimeout)
      MESSAGE_LIST_REGISTRY.delete(this.messageList)
    }

    this.messageList = null
    this.messageListRegistry = null
  }

  /**
   * Get the tail message ID from the DOM (O(1)) by reading the list's last element child.
   *
   * @param {HTMLElement|null} list - The messages list element
   * @returns {string|null} The tail message ID, or null if not available
   */
  domTailMessageId(list) {
    if (!list) return null

    const tailElement = list.lastElementChild
    if (!tailElement) return null

    return tailElement.dataset.messageActionsMessageIdValue || null
  }

  /**
   * Set the tail message ID on the messages list container (only if changed).
   *
   * @param {HTMLElement|null} list - The messages list element
   * @param {string|number|null} tailMessageId - The tail message ID
   */
  setTailMessageId(list, tailMessageId) {
    if (!list) return

    const next = tailMessageId == null ? "" : String(tailMessageId)
    const current = list.dataset.tailMessageId || ""

    if (current === next) return

    list.dataset.tailMessageId = next
  }

  /**
   * If this message is currently the last element in the list, sync the container's tail ID.
   * This fixes stale data-tail-message-id when Turbo broadcasts append messages.
   */
  syncTailMessageIdIfIAmTail() {
    const list = this.messagesList()
    if (!list) return

    if (list.lastElementChild === this.element) {
      this.setTailMessageId(list, this.messageIdValue)
    }
  }

  /**
   * Check if this message is the tail (last) message in the conversation.
   * Uses the explicit tail message ID from DOM attribute for reliability.
   * Falls back to DOM position if attribute is not set.
   *
   * @returns {boolean} True if this is the last message in the list
   */
  isTailMessage() {
    const list = this.messagesList()
    const domTailMessageId = this.domTailMessageId(list)

    // Prefer the DOM tail (fast + always correct after Turbo appends/removes)
    if (domTailMessageId) {
      // Keep the explicit tail ID in sync so other controllers can do O(1) comparisons.
      if (this.findTailMessageId() !== domTailMessageId) {
        this.setTailMessageId(list, domTailMessageId)
      }

      return String(this.messageIdValue) === domTailMessageId
    }

    const tailMessageId = this.findTailMessageId()

    // Use explicit tail ID if available
    if (tailMessageId) {
      return String(this.messageIdValue) === String(tailMessageId)
    }

    // Fallback to DOM position check
    if (!list) return false

    const messages = list.querySelectorAll("[data-controller~='message-actions']")
    if (messages.length === 0) return false

    return messages[messages.length - 1] === this.element
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
    event.preventDefault()

    const content = this.getMessageContent()
    if (!content) return

    try {
      const ok = await copyTextToClipboard(content)
      if (!ok) {
        logger.error("Failed to copy to clipboard")
      }
      showToast(ok ? "Copied to clipboard" : "Failed to copy", ok ? "success" : "error")
    } catch (error) {
      logger.error("Failed to copy:", error)
      showToast("Failed to copy", "error")
    }
  }

  /**
   * Handle keyboard shortcuts in edit mode.
   */
  handleEditKeydown(event) {
    // Escape to cancel
    if (event.key === "Escape") {
      event.preventDefault()
      this.cancelEdit()
    }

    // Ctrl/Cmd + Enter to save
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault()
      const form = event.target.closest("form")
      if (form) {
        form.requestSubmit()
      }
    }
  }

  /**
   * Cancel inline editing.
   */
  cancelEdit() {
    // Find and click the cancel link
    const cancelLink = this.element.querySelector("[data-action*='cancel']") ||
                       this.element.querySelector("a.btn-ghost")
    if (cancelLink) {
      cancelLink.click()
    }
  }

  /**
   * Handle escape key press.
   */
  handleEscape(event) {
    if (event.key === "Escape" && this.editingValue) {
      this.cancelEdit()
    }
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
    const button = event.currentTarget
    const icon = button.querySelector("span[class*='icon-']")

    if (icon) {
      // Add spinning animation
      icon.classList.add("animate-spin")
    }

    // The form will submit via Turbo, animation will be cleared on page update
  }

  /**
   * Trigger the branch action from the Branch CTA button.
   * Programmatically clicks the regular branch button to reuse its form submission.
   */
  triggerBranch(event) {
    event.preventDefault()

    if (this.hasBranchBtnTarget) {
      this.branchBtnTarget.click()
    } else {
      showToast("Branch action not available", "warning")
    }
  }

  /**
   * Show debug info for this message by opening the run detail modal.
   * The run data is stored in the data-run-data attribute of the clicked button.
   */
  showDebug(event) {
    event.preventDefault()

    const button = event.currentTarget
    const runDataJson = button.dataset.runData

    if (!runDataJson) {
      showToast("No debug data available", "warning")
      return
    }

    let runData
    try {
      runData = JSON.parse(runDataJson)
    } catch (e) {
      logger.error("Failed to parse run data:", e)
      showToast("Failed to load debug data", "error")
      return
    }

    // Find the run detail modal and call its showRun method
    const modal = document.getElementById("run_detail_modal")
    if (!modal) {
      logger.error("Run detail modal not found")
      showToast("Debug modal not found", "error")
      return
    }

    // Get the Stimulus controller for the modal
    const modalController = this.application.getControllerForElementAndIdentifier(modal, "run-detail-modal")
    if (modalController) {
      modalController.showRun(runData)
    } else {
      logger.error("Run detail modal controller not found")
      showToast("Debug modal controller not found", "error")
    }
  }

  /**
   * Get the message content text.
   */
  getMessageContent() {
    // Try to get content from the template (raw markdown)
    // Note: template elements store content in .content property
    const template = this.element.querySelector("template[data-markdown-target='content']")
    if (template) {
      return template.content.textContent.trim()
    }

    // Fallback to rendered content
    const output = this.element.querySelector("[data-markdown-target='output']")
    if (output) {
      return output.textContent.trim()
    }

    // Last resort: message text content
    const mesText = this.element.querySelector(".mes-text")
    if (mesText) {
      return mesText.textContent.trim()
    }

    return null
  }

}
