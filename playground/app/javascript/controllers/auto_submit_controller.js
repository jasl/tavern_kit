import { Controller } from "@hotwired/stimulus"

const inflightByKey = new Map()

export default class extends Controller {
  static values = {
    debounce: { type: Number, default: 0 }
  }

  submitTimeout = null
  submitKey = null
  pendingSubmit = false

  connect() {
    // Release any in-flight lock when Turbo finishes the submission (success or error).
    this.submitKey = this.element.action || this.element.getAttribute("action") || ""
    this.element.addEventListener("turbo:submit-end", this.#handleSubmitEnd)
  }

  disconnect() {
    if (this.submitTimeout) {
      clearTimeout(this.submitTimeout)
      this.submitTimeout = null
    }

    this.element.removeEventListener("turbo:submit-end", this.#handleSubmitEnd)
    this.#releaseLock()
  }

  submit(event) {
    // Debounce only for `input` events (typing), so toggles/selects stay responsive.
    if (this.debounceValue > 0 && event?.type === "input") {
      if (this.submitTimeout) clearTimeout(this.submitTimeout)
      this.submitTimeout = setTimeout(() => {
        this.submitTimeout = null
        this.#requestSubmitWithLock()
      }, this.debounceValue)
      return
    }

    if (this.submitTimeout) {
      clearTimeout(this.submitTimeout)
      this.submitTimeout = null
    }

    this.#requestSubmitWithLock()
  }

  #handleSubmitEnd = () => {
    this.#releaseLock()

    // If a submit was requested while a request was in-flight, submit once more
    // to flush the latest control values (coalescing multiple changes).
    if (this.pendingSubmit) {
      this.pendingSubmit = false
      this.#requestSubmitWithLock()
    }
  }

  #lockKey() {
    return String(this.submitKey || "")
  }

  #requestSubmitWithLock() {
    const key = this.#lockKey()
    if (key) {
      if (inflightByKey.get(key)) {
        this.pendingSubmit = true
        return
      }
      inflightByKey.set(key, true)
    }

    this.element.requestSubmit()
  }

  #releaseLock() {
    const key = this.#lockKey()
    if (!key) return

    inflightByKey.delete(key)
  }
}
