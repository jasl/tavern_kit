import { Controller } from "@hotwired/stimulus"
import { copyTextToClipboard } from "../dom_helpers"

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
    const success = await copyTextToClipboard(this.textValue)

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
}
