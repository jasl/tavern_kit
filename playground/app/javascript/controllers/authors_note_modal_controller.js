import { Controller } from "@hotwired/stimulus"

/**
 * Author's Note Modal Controller
 *
 * Manages the Author's Note editing modal for conversations.
 * Handles opening/closing, character count, clearing, and form submission.
 */
export default class extends Controller {
  static targets = ["textarea", "charCount", "submitButton"]
  static values = { conversationId: Number }

  connect() {
    this.modal = this.element
    this.updateCharCount()
  }

  /**
   * Open the modal.
   */
  open() {
    this.modal.showModal()
  }

  /**
   * Close the modal.
   */
  close() {
    this.modal.close()
  }

  /**
   * Update character count display.
   */
  updateCharCount() {
    if (!this.hasTextareaTarget || !this.hasCharCountTarget) return

    const count = this.textareaTarget.value.length
    this.charCountTarget.textContent = `${count} chars`
  }

  /**
   * Clear the textarea content.
   */
  clear() {
    if (!this.hasTextareaTarget) return

    this.textareaTarget.value = ""
    this.updateCharCount()
  }

  /**
   * Handle form submission response.
   * Closes the modal on successful save.
   *
   * @param {Event} event - The turbo:submit-end event
   */
  handleSubmit(event) {
    if (event.detail.success) {
      this.close()
      this.showToast("Author's Note saved", "success")
    } else {
      this.showToast("Failed to save Author's Note", "error")
    }
  }

  /**
   * Show a toast notification.
   *
   * @param {string} message - The message to display
   * @param {string} type - The toast type (info, success, warning, error)
   */
  showToast(message, type = "info") {
    const event = new CustomEvent("toast:show", {
      detail: { message, type, duration: 3000 },
      bubbles: true,
      cancelable: true,
    })
    window.dispatchEvent(event)
  }

  /**
   * Handle textarea input for character count updates.
   */
  textareaTargetConnected(element) {
    element.addEventListener("input", () => this.updateCharCount())
  }
}
