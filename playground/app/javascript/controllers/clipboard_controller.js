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

  disconnect() {
    if (this.__restoreTimerId) {
      clearTimeout(this.__restoreTimerId)
      this.__restoreTimerId = null
    }
  }

  feedbackNodes(iconName, text) {
    const icon = document.createElement("span")
    icon.className = `icon-[lucide--${iconName}] size-4`

    const label = document.createElement("span")
    label.textContent = text

    return [icon, label]
  }

  async copy() {
    if (!this.textValue) return

    const success = await copyTextToClipboard(this.textValue)

    if (this.__restoreTimerId) {
      clearTimeout(this.__restoreTimerId)
      this.__restoreTimerId = null
    }

    const originalNodes = Array.from(this.element.childNodes).map(node => node.cloneNode(true))

    this.element.replaceChildren(...(
      success
        ? this.feedbackNodes("check", this.successTextValue)
        : this.feedbackNodes("x", "Failed")
    ))

    this.__restoreTimerId = setTimeout(() => {
      this.element.replaceChildren(...originalNodes)
      this.__restoreTimerId = null
    }, this.durationValue)
  }
}
