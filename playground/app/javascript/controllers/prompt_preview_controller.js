import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { htmlRequest } from "../request_helpers"
import { renderAlertBox } from "../ui/alert_box"

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

      const { response, html } = await htmlRequest(this.urlValue, {
        method: "POST",
        body: { content }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

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
      this.contentTarget.replaceChildren(renderAlertBox({
        variant: "error",
        icon: "alert-circle",
        title: message || "Failed to load prompt preview"
      }))
    }

    if (this.hasModalTarget) {
      this.modalTarget.showModal()
    }
  }

}
