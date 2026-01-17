import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    debounce: { type: Number, default: 0 }
  }

  submitTimeout = null

  disconnect() {
    if (this.submitTimeout) {
      clearTimeout(this.submitTimeout)
      this.submitTimeout = null
    }
  }

  submit(event) {
    // Debounce only for `input` events (typing), so toggles/selects stay responsive.
    if (this.debounceValue > 0 && event?.type === "input") {
      if (this.submitTimeout) clearTimeout(this.submitTimeout)
      this.submitTimeout = setTimeout(() => {
        this.submitTimeout = null
        this.element.requestSubmit()
      }, this.debounceValue)
      return
    }

    if (this.submitTimeout) {
      clearTimeout(this.submitTimeout)
      this.submitTimeout = null
    }

    this.element.requestSubmit()
  }
}
