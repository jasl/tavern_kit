import { Controller } from "@hotwired/stimulus"
import { connect, debounceSave as debounceSaveNow, disconnect, save as saveNow } from "../ui/authors_note_form/save"

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
    connect(this)
  }

  disconnect() {
    disconnect(this)
  }

  /**
   * Debounced save - called on input events for textarea.
   */
  debounceSave() {
    debounceSaveNow(this)
  }

  /**
   * Immediate save - called on change events for selects/toggles.
   */
  save() {
    saveNow(this)
  }

}
