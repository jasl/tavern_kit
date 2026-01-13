import { Controller } from "@hotwired/stimulus"
import { isSettingInput } from "../ui/settings_form/inputs"
import { saveNow, scheduleChange } from "../ui/settings_form/autosave"

/**
 * Settings form controller for auto-save with JSON PATCH (nested merge patch).
 *
 * Collects setting values from data attributes and sends PATCH requests
 * with debouncing.
 *
 * @example HTML structure
 *   <div data-controller="settings-form"
 *        data-settings-form-url-value="/spaces/1/participants/123"
 *        data-settings-form-debounce-value="300">
 *     <input data-setting-key="max_context_tokens" data-setting-type="integer"
 *            data-setting-path="settings.llm.providers.openai.generation.max_context_tokens">
 *   </div>
 */
export default class extends Controller {
  static targets = ["status", "savedAt"]
  static values = {
    url: String,
    debounce: { type: Number, default: 300 },
    schemaVersion: { type: String, default: "participant_llm_v1" },
    settingsVersion: { type: Number, default: 0 },
    resourceKey: { type: String, default: "participant" }
  }

  // Track pending changes and state
  pendingChanges = new Map()
  saveTimeout = null
  isSaving = false
  boundHandleInput = null
  boundHandleChange = null

  connect() {
    // Set up event listeners for all setting inputs
    this.boundHandleInput = this.handleInput.bind(this)
    this.boundHandleChange = this.handleChange.bind(this)
    this.element.addEventListener("input", this.boundHandleInput)
    this.element.addEventListener("change", this.boundHandleChange)
  }

  disconnect() {
    // Remove event listeners to avoid leaks when the controller disconnects
    if (this.boundHandleInput) {
      this.element.removeEventListener("input", this.boundHandleInput)
    }
    if (this.boundHandleChange) {
      this.element.removeEventListener("change", this.boundHandleChange)
    }

    // Clear any pending saves
    if (this.saveTimeout) {
      clearTimeout(this.saveTimeout)
    }
  }

  /**
   * Handle input events (for text, range, etc.)
   */
  handleInput(event) {
    const input = event.target
    if (!isSettingInput(input)) return

    scheduleChange(this, input)
  }

  /**
   * Handle change events (for select, checkbox, etc.)
   */
  handleChange(event) {
    const input = event.target
    if (!isSettingInput(input)) return

    scheduleChange(this, input)
  }

  /**
   * Force save immediately (called externally).
   */
  saveNow() {
    saveNow(this)
  }
}
