import { Controller } from "@hotwired/stimulus"

/**
 * Clipboard Controller
 *
 * A simple controller for copying text to the clipboard.
 *
 * Usage:
 *   <button data-controller="clipboard"
 *           data-clipboard-text-value="Text to copy"
 *           data-action="click->clipboard#copy">
 *     Copy
 *   </button>
 *
 * The button text will temporarily change to indicate success/failure.
 */
export default class extends Controller {
  static values = {
    text: String,
    successText: { type: String, default: "Copied!" },
    duration: { type: Number, default: 2000 }
  }

  async copy() {
    if (!this.textValue) return

    const originalHTML = this.element.innerHTML
    let success = false

    try {
      // Try modern clipboard API first
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(this.textValue)
        success = true
      } else {
        // Fallback for older browsers or non-secure contexts
        success = this.fallbackCopy()
      }
    } catch {
      // navigator.clipboard.writeText failed, try fallback
      success = this.fallbackCopy()
    }

    if (success) {
      // Show success feedback
      this.element.innerHTML = `<span class="icon-[lucide--check] size-4"></span> ${this.successTextValue}`
    } else {
      // Show error feedback
      this.element.innerHTML = `<span class="icon-[lucide--x] size-4"></span> Failed`
    }

    setTimeout(() => {
      this.element.innerHTML = originalHTML
    }, this.durationValue)
  }

  /**
   * Fallback copy method using a temporary textarea and execCommand.
   * Works in non-secure contexts where navigator.clipboard is not available.
   */
  fallbackCopy() {
    const textarea = document.createElement("textarea")
    textarea.value = this.textValue
    textarea.style.position = "fixed"
    textarea.style.left = "-9999px"
    textarea.style.top = "-9999px"
    document.body.appendChild(textarea)
    textarea.focus()
    textarea.select()

    let success = false
    try {
      success = document.execCommand("copy")
    } catch {
      success = false
    }

    document.body.removeChild(textarea)
    return success
  }
}
