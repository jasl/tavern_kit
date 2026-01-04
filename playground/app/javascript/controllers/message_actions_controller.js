import { Controller } from "@hotwired/stimulus"

/**
 * Message Actions Controller
 *
 * Handles message action buttons: edit, delete, regenerate, copy.
 * Provides enhanced UX with inline editing and toast confirmations.
 *
 * @example HTML structure
 *   <div data-controller="message-actions" data-message-actions-message-id-value="123">
 *     <button data-action="click->message-actions#edit">Edit</button>
 *     <button data-action="click->message-actions#delete">Delete</button>
 *     <button data-action="click->message-actions#copy">Copy</button>
 *   </div>
 */
export default class extends Controller {
  static targets = ["content", "textarea", "actions"]
  static values = {
    messageId: Number,
    editing: { type: Boolean, default: false },
    deleting: { type: Boolean, default: false }
  }

  connect() {
    // Bind escape key handler for edit mode
    this.handleEscape = this.handleEscape.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleEscape)
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
