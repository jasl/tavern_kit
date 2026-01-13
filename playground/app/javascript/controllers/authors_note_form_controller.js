import { Controller } from "@hotwired/stimulus"
import logger from "../logger"

/**
 * Author's Note Form Controller
 *
 * Handles auto-save functionality for Character Author's Note settings.
 * Sends JSON PATCH requests to update authors_note_settings.
 */
export default class extends Controller {
  static targets = [
    "enableToggle",
    "content",
    "position",
    "depth",
    "role",
    "combineMode",
    "charCount",
    "status",
    "savedAt"
  ]

  static values = {
    url: String,
    debounce: { type: Number, default: 500 }
  }

  connect() {
    this.debounceTimer = null
    this.updateCharCount()
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }

  /**
   * Debounced save - called on input events for textarea.
   */
  debounceSave() {
    this.updateCharCount()

    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    this.debounceTimer = setTimeout(() => {
      this.save()
    }, this.debounceValue)
  }

  /**
   * Immediate save - called on change events for selects/toggles.
   */
  save() {
    const data = this.collectFormData()
    this.sendUpdate(data)
  }

  /**
   * Collect all form data into authors_note_settings object.
   */
  collectFormData() {
    const settings = {}

    if (this.hasEnableToggleTarget) {
      settings.use_character_authors_note = this.enableToggleTarget.checked
    }

    if (this.hasContentTarget) {
      settings.authors_note = this.contentTarget.value
    }

    if (this.hasPositionTarget) {
      settings.authors_note_position = this.positionTarget.value
    }

    if (this.hasDepthTarget) {
      const depth = parseInt(this.depthTarget.value, 10)
      settings.authors_note_depth = isNaN(depth) ? 4 : Math.max(0, depth)
    }

    if (this.hasRoleTarget) {
      settings.authors_note_role = this.roleTarget.value
    }

    if (this.hasCombineModeTarget) {
      settings.character_authors_note_position = this.combineModeTarget.value
    }

    return settings
  }

  /**
   * Send update to server.
   */
  async sendUpdate(settings) {
    this.setStatus("saving")

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ authors_note_settings: settings })
      })

      const result = await response.json()

      if (result.ok) {
        this.setStatus("saved")
        this.setSavedAt(result.saved_at)
      } else {
        this.setStatus("error")
        logger.error("Failed to save:", result.errors)
      }
    } catch (error) {
      this.setStatus("error")
      logger.error("Save error:", error)
    }
  }

  /**
   * Update character count display.
   */
  updateCharCount() {
    if (!this.hasCharCountTarget || !this.hasContentTarget) return

    const count = this.contentTarget.value.length
    this.charCountTarget.textContent = `${count} chars`
  }

  /**
   * Set status badge.
   */
  setStatus(status) {
    if (!this.hasStatusTarget) return

    const statusMap = {
      saving: { text: "Saving...", class: "badge-warning" },
      saved: { text: "Saved", class: "badge-success" },
      error: { text: "Error", class: "badge-error" }
    }

    const config = statusMap[status] || { text: "", class: "badge-ghost" }

    this.statusTarget.textContent = config.text
    this.statusTarget.className = `badge badge-sm ${config.class}`

    // Auto-hide saved status after 2 seconds
    if (status === "saved") {
      setTimeout(() => {
        if (this.statusTarget.textContent === "Saved") {
          this.statusTarget.textContent = ""
          this.statusTarget.className = "badge badge-sm badge-ghost"
        }
      }, 2000)
    }
  }

  /**
   * Set saved timestamp.
   */
  setSavedAt(isoString) {
    if (!this.hasSavedAtTarget) return

    try {
      const date = new Date(isoString)
      this.savedAtTarget.textContent = `Last saved: ${date.toLocaleTimeString()}`
    } catch {
      this.savedAtTarget.textContent = ""
    }
  }

  /**
   * Get CSRF token from meta tag.
   */
  get csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute("content") : ""
  }
}
