import { Controller } from "@hotwired/stimulus"
import { setStatusBadge } from "../ui/status_badge"

/**
 * Save Indicator Controller
 *
 * Unifies "Saved" feedback in the Conversation right sidebar for:
 * - Turbo form submissions (Space tab quick settings / auto-submit forms)
 * - Fetch-based operations that dispatch `save-indicator:status` events (e.g. preset switching)
 *
 * It reuses the existing footer badge/timestamp elements already used by settings-form.
 */
export default class extends Controller {
  connect() {
    this.statusEl = this.element.querySelector("[data-settings-form-target='status']")
    this.savedAtEl = this.element.querySelector("[data-settings-form-target='savedAt']")

    this.handleSubmitStart = this.handleSubmitStart.bind(this)
    this.handleSubmitEnd = this.handleSubmitEnd.bind(this)
    this.handleExternalStatus = this.handleExternalStatus.bind(this)

    // Use capture so we still receive non-bubbling Turbo events (if any).
    this.element.addEventListener("turbo:submit-start", this.handleSubmitStart, true)
    this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd, true)
    window.addEventListener("save-indicator:status", this.handleExternalStatus)

    this.replayLastStatusIfFresh()
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.handleSubmitStart, true)
    this.element.removeEventListener("turbo:submit-end", this.handleSubmitEnd, true)
    window.removeEventListener("save-indicator:status", this.handleExternalStatus)
  }

  replayLastStatusIfFresh() {
    const last = window.__saveIndicatorLast
    const at = last?.at
    const status = last?.status

    if (!status || !at) return
    if (Date.now() - at > 5000) return

    this.handleExternalStatus({ detail: last })

    // Prevent replaying on future connects.
    if (status !== "saving") {
      window.__saveIndicatorLast = null
    }
  }

  handleSubmitStart(event) {
    const form = event?.target
    if (!(form instanceof HTMLFormElement)) return
    this.setStatus("saving")
  }

  handleSubmitEnd(event) {
    const form = event?.target
    if (!(form instanceof HTMLFormElement)) return

    const success = Boolean(event?.detail?.success)
    if (success) {
      this.markSaved()
    } else {
      this.setStatus("error")
    }
  }

  handleExternalStatus(event) {
    const status = event?.detail?.status
    const message = event?.detail?.message || null

    if (!status) return

    if (status === "saved") {
      this.markSaved()
      return
    }

    this.setStatus(status, message)
  }

  setStatus(status, message = null) {
    if (!this.statusEl) return

    setStatusBadge(this.statusEl, status, {
      message,
      idleVariant: "badge-ghost"
    })
  }

  markSaved() {
    this.setStatus("saved")
    if (this.savedAtEl) this.savedAtEl.textContent = new Date().toLocaleTimeString()
  }
}

