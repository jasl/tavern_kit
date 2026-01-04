import { Controller } from "@hotwired/stimulus"

/**
 * Message form controller for handling message input interactions.
 *
 * Provides keyboard shortcuts for submitting messages:
 * - Enter (without modifiers): Submit the form
 * - Shift+Enter: Insert newline (default browser behavior)
 *
 * Clears the textarea after successful form submission.
 *
 * @example HTML structure
 *   <form data-controller="message-form">
 *     <textarea data-action="keydown->message-form#handleKeydown"
 *               data-message-form-target="textarea"></textarea>
 *     <button type="submit">Send</button>
 *   </form>
 */
export default class extends Controller {
  static targets = ["textarea", "generateBtn"]
  static values = {
    generateUrl: String
  }

  connect() {
    // Listen for turbo:submit-end on the form element
    this.handleSubmitEnd = this.handleSubmitEnd.bind(this)
    this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
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
      event.preventDefault()

      // Find and submit the form
      const form = this.element.closest("form") || this.element.querySelector("form")
      if (form) {
        // Use requestSubmit to trigger validation and submit events
        form.requestSubmit()
      }
    }
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
      // Use Turbo's statusCode getter for reliable status retrieval
      const status = event.detail?.fetchResponse?.statusCode

      if (status === 423) {
        this.showToast("AI is generating a response. Please wait…", "warning")
      } else if (status === 409) {
        this.showToast("Message not sent due to a conflict. Please try again.", "warning")
      } else {
        this.showToast("Message not sent. Please try again.", "error")
      }

      return
    }

    if (event.detail?.fetchResponse && textarea) {
      textarea.value = ""
    }
  }

  showToast(message, type = "info") {
    let container = document.getElementById("toast-container")
    if (!container) {
      container = document.createElement("div")
      container.id = "toast-container"
      container.className = "toast toast-end toast-bottom z-50"
      document.body.appendChild(container)
    }

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

    setTimeout(() => {
      toast.classList.add("opacity-0", "transition-opacity")
      setTimeout(() => toast.remove(), 300)
    }, 3000)
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  /**
   * Trigger AI response generation without a specific speaker.
   * Uses random speaker selection for manual mode, or SpeakerSelector for other modes.
   */
  generate() {
    if (!this.generateUrlValue) return

    fetch(this.generateUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept": "text/vnd.turbo-stream.html"
      }
    }).then(response => {
      if (!response.ok) {
        if (response.status === 422) {
          this.showToast("No AI character available to respond.", "warning")
        } else {
          this.showToast("Failed to generate response.", "error")
        }
      }
    }).catch(() => {
      this.showToast("Failed to generate response.", "error")
    })
  }

  /**
   * Force a specific character to respond (Force Talk).
   * Works even for muted characters.
   */
  forceTalk(event) {
    if (!this.generateUrlValue) return

    const speakerId = event.currentTarget.dataset.speakerId
    if (!speakerId) return

    const url = new URL(this.generateUrlValue, window.location.origin)
    url.searchParams.set("speaker_id", speakerId)

    fetch(url.toString(), {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept": "text/vnd.turbo-stream.html"
      }
    }).then(response => {
      if (!response.ok) {
        if (response.status === 422) {
          this.showToast("Speaker not available.", "warning")
        } else {
          this.showToast("Failed to trigger response.", "error")
        }
      }
    }).catch(() => {
      this.showToast("Failed to trigger response.", "error")
    })
  }
}
