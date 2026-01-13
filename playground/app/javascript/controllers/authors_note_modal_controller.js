import { Controller } from "@hotwired/stimulus"
import { showToast } from "../request_helpers"

/**
 * Author's Note Modal Controller
 *
 * Manages the Author's Note editing modal for conversations.
 * Handles opening/closing, character count, clearing, form submission,
 * and toggling depth field visibility based on position selection.
 */
export default class extends Controller {
  static targets = ["textarea", "charCount", "submitButton", "depthField", "depthRoleRow"]
  static values = { conversationId: Number }

  connect() {
    this.modal = this.element
    this.updateCharCount()
    this.initializeDepthVisibility()
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
   * Toggle depth field visibility based on position selection.
   * Depth is only relevant when position is "in_chat".
   */
  toggleDepth() {
    if (!this.hasDepthFieldTarget) return

    const selectedPosition = this.getSelectedPosition()
    const showDepth = selectedPosition === "in_chat"

    this.depthFieldTarget.classList.toggle("opacity-50", !showDepth)
    this.depthFieldTarget.classList.toggle("pointer-events-none", !showDepth)

    // Disable the input when not in_chat
    const depthInput = this.depthFieldTarget.querySelector("input")
    if (depthInput) {
      depthInput.disabled = !showDepth
    }
  }

  /**
   * Initialize depth field visibility based on current selection.
   */
  initializeDepthVisibility() {
    this.toggleDepth()
  }

  /**
   * Get the currently selected position value.
   */
  getSelectedPosition() {
    const selectedRadio = this.element.querySelector('input[name="conversation[authors_note_position]"]:checked')
    return selectedRadio ? selectedRadio.value : "in_chat"
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
      showToast("Author's Note saved", "success")
    } else {
      showToast("Failed to save Author's Note", "error")
    }
  }

  /**
   * Handle textarea input for character count updates.
   */
  textareaTargetConnected(element) {
    element.addEventListener("input", () => this.updateCharCount())
  }
}
