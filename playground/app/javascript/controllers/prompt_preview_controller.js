import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { getCsrfToken } from "../request_helpers"
import { escapeHtml } from "../dom_helpers"

/**
 * Prompt Preview Controller
 *
 * Manages prompt preview functionality - shows users what will be sent to the LLM.
 *
 * @example HTML structure
 *   <div data-controller="prompt-preview"
 *        data-prompt-preview-url-value="/spaces/123/prompt_preview">
 *     <textarea data-prompt-preview-target="textarea"></textarea>
 *     <button data-action="prompt-preview#preview">Preview</button>
 *     <dialog data-prompt-preview-target="modal">
 *       <div data-prompt-preview-target="content"></div>
 *     </dialog>
 *   </div>
 */
export default class extends Controller {
  static targets = ["textarea", "modal", "content", "previewBtn"]
  static values = {
    url: String,
    loading: { type: Boolean, default: false }
  }

  /**
   * Preview the prompt.
   * Fetches the rendered prompt from the server and displays it in a modal.
   */
  async preview(event) {
    event?.preventDefault()

    if (this.loadingValue) return

    this.loadingValue = true
    this.updateButtonState()

    try {
      const content = this.hasTextareaTarget ? this.textareaTarget.value : ""

      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCsrfToken(),
          "Accept": "text/html"
        },
        body: JSON.stringify({ content })
      })

      const html = await response.text()

      if (this.hasContentTarget) {
        this.contentTarget.innerHTML = html
      }

      if (this.hasModalTarget) {
        this.modalTarget.showModal()
      }
    } catch (error) {
      logger.error("Prompt preview failed:", error)
      this.showError("Failed to load prompt preview")
    } finally {
      this.loadingValue = false
      this.updateButtonState()
    }
  }

  /**
   * Close the preview modal.
   */
  close() {
    if (this.hasModalTarget) {
      this.modalTarget.close()
    }
  }

  /**
   * Update button state based on loading.
   */
  updateButtonState() {
    if (this.hasPreviewBtnTarget) {
      this.previewBtnTarget.disabled = this.loadingValue
    }
  }

  /**
   * Show an error message in the modal.
   */
  showError(message) {
    if (this.hasContentTarget) {
      this.contentTarget.innerHTML = `
        <div class="alert alert-error">
          <span class="icon-[lucide--alert-circle] size-5"></span>
          <span>${escapeHtml(message)}</span>
        </div>
      `
    }

    if (this.hasModalTarget) {
      this.modalTarget.showModal()
    }
  }

}
