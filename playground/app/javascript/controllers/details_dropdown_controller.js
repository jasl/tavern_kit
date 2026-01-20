import { Controller } from "@hotwired/stimulus"

/**
 * DetailsDropdown Controller
 *
 * Adds "click outside to close" and Escape-to-close for <details>-based dropdowns.
 * This is especially helpful inside <dialog> and Turbo Frames where CSS-only
 * click-away overlays can be unreliable.
 */
export default class extends Controller {
  connect() {
    this._onToggle = this._onToggle.bind(this)
    this._onDocumentClick = this._onDocumentClick.bind(this)
    this._onDocumentKeydown = this._onDocumentKeydown.bind(this)

    this.element.addEventListener("toggle", this._onToggle)

    if (this.element.open) {
      this.#enableOutsideClose()
    }
  }

  disconnect() {
    this.element.removeEventListener("toggle", this._onToggle)
    this.#disableOutsideClose()
  }

  close() {
    this.element.open = false
  }

  _onToggle() {
    if (this.element.open) {
      this.#enableOutsideClose()
    } else {
      this.#disableOutsideClose()
    }
  }

  _onDocumentClick(event) {
    if (!this.element.open) return
    if (this.element.contains(event.target)) return
    this.close()
  }

  _onDocumentKeydown(event) {
    if (!this.element.open) return
    if (event.key !== "Escape") return
    this.close()
  }

  #enableOutsideClose() {
    if (this._outsideCloseEnabled) return
    this._outsideCloseEnabled = true

    // Capture phase ensures we close even if other handlers stop propagation.
    document.addEventListener("click", this._onDocumentClick, true)
    document.addEventListener("keydown", this._onDocumentKeydown, true)
  }

  #disableOutsideClose() {
    if (!this._outsideCloseEnabled) return
    this._outsideCloseEnabled = false

    document.removeEventListener("click", this._onDocumentClick, true)
    document.removeEventListener("keydown", this._onDocumentKeydown, true)
  }
}
