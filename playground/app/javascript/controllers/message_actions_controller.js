import { Controller } from "@hotwired/stimulus"

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
 * @example HTML structure
 *   <div data-controller="message-actions"
 *        data-message-actions-message-id-value="123"
 *        data-message-role="user"
 *        data-message-participant-id="456">
 *     <button data-message-actions-target="editButton">Edit</button>
 *     <button data-message-actions-target="deleteButton">Delete</button>
 *     <button data-action="click->message-actions#copy">Copy</button>
 *   </div>
 */
export default class extends Controller {
  static targets = ["content", "textarea", "actions", "editButton", "deleteButton", "swipeNav", "regenerateButton"]
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

    // Apply visibility rules
    this.updateButtonVisibility()

    // Watch for changes to the messages list (for Turbo broadcasts adding/removing messages)
    this.setupMutationObserver()
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleEscape)

    // Clean up mutation observer
    if (this.mutationObserver) {
      this.mutationObserver.disconnect()
      this.mutationObserver = null
    }
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
   * Check if this message is the tail (last) message in the conversation.
   * Uses DOM position to determine this, which works correctly after Turbo broadcasts.
   *
   * @returns {boolean} True if this is the last message in the list
   */
  isTailMessage() {
    const list = this.element.closest("[data-chat-scroll-target='list']")
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
   * Set up a MutationObserver to watch for changes to the messages list.
   * This re-evaluates visibility when messages are added or removed via Turbo broadcasts.
   */
  setupMutationObserver() {
    const list = this.element.closest("[data-chat-scroll-target='list']")
    if (!list) return

    // Debounce the update to avoid excessive recalculations
    let updateTimeout = null
    const debouncedUpdate = () => {
      if (updateTimeout) clearTimeout(updateTimeout)
      updateTimeout = setTimeout(() => {
        this.updateButtonVisibility()
      }, 50)
    }

    this.mutationObserver = new MutationObserver((mutations) => {
      // Check if any children were added or removed (messages list changed)
      const hasChildChanges = mutations.some(
        (mutation) => mutation.type === "childList" && mutation.addedNodes.length > 0 || mutation.removedNodes.length > 0
      )

      if (hasChildChanges) {
        debouncedUpdate()
      }
    })

    this.mutationObserver.observe(list, {
      childList: true,
      subtree: false
    })
  }

  /**
   * Copy message content to clipboard.
   */
  async copy(event) {
    event.preventDefault()

    const content = this.getMessageContent()
    if (!content) return

    try {
      await navigator.clipboard.writeText(content)
      this.showToast("Copied to clipboard", "success")
    } catch (err) {
      console.error("Failed to copy:", err)
      this.showToast("Failed to copy", "error")
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
  confirmDelete(event) {
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

    // Last resort: chat bubble content
    const bubble = this.element.querySelector(".chat-bubble")
    if (bubble) {
      return bubble.textContent.trim()
    }

    return null
  }

  /**
   * Show a toast notification.
   */
  showToast(message, type = "info") {
    // Find or create toast container
    let container = document.getElementById("toast-container")
    if (!container) {
      container = document.createElement("div")
      container.id = "toast-container"
      container.className = "toast toast-end toast-bottom z-50"
      document.body.appendChild(container)
    }

    // Create toast element
    const toast = document.createElement("div")
    const alertClass = {
      success: "alert-success",
      error: "alert-error",
      warning: "alert-warning",
      info: "alert-info"
    }[type] || "alert-info"

    toast.className = `alert ${alertClass} shadow-lg`
    toast.innerHTML = `<span>${this.escapeHtml(message)}</span>`

    container.appendChild(toast)

    // Auto-remove after 3 seconds
    setTimeout(() => {
      toast.classList.add("opacity-0", "transition-opacity")
      setTimeout(() => toast.remove(), 300)
    }, 3000)
  }

  /**
   * Escape HTML to prevent XSS.
   */
  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
