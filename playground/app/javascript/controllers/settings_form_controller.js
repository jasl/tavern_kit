import { Controller } from "@hotwired/stimulus"
import logger from "../logger"

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
    if (!this.isSettingInput(input)) return

    this.scheduleChange(input)
  }

  /**
   * Handle change events (for select, checkbox, etc.)
   */
  handleChange(event) {
    const input = event.target
    if (!this.isSettingInput(input)) return

    this.scheduleChange(input)
  }

  /**
   * Force save immediately (called externally).
   */
  saveNow() {
    if (this.saveTimeout) {
      clearTimeout(this.saveTimeout)
    }
    this.performSave()
  }

  // Private methods

  isSettingInput(element) {
    // Require both data-setting-key and data-setting-path for valid setting inputs
    return element.hasAttribute("data-setting-key") && element.hasAttribute("data-setting-path")
  }

  scheduleChange(input) {
    const key = input.dataset.settingKey
    const path = input.dataset.settingPath
    const type = input.dataset.settingType
    const value = this.getInputValue(input, type)

    // Store the change (settings.* or top-level columns like llm_provider_id)
    this.pendingChanges.set(path || key, { key, path, type, value })

    // Update status
    this.updateStatus("pending")

    // Provider changes should apply immediately to update gating context.
    if (path === "llm_provider_id") {
      this.saveNow()
      return
    }

    // Debounce the save for settings fields
    if (this.saveTimeout) clearTimeout(this.saveTimeout)
    this.saveTimeout = setTimeout(() => this.performSave(), this.debounceValue)
  }

  async performSave() {
    if (this.pendingChanges.size === 0 || this.isSaving) return

    this.isSaving = true
    this.updateStatus("saving")

    const settingsPatch = {}
    const dataPatch = {}
    const columns = {}

    this.pendingChanges.forEach((change) => {
      if (change.path && change.path.startsWith("settings.")) {
        this.assignNested(settingsPatch, change.path.replace(/^settings\./, ""), change.value)
      } else if (change.path && change.path.startsWith("data.")) {
        this.assignNested(dataPatch, change.path.replace(/^data\./, ""), change.value)
      } else if (change.path) {
        columns[change.path] = change.value
      }
    })

    // Bail out if there's no actual data to save (e.g., fields without data-setting-path)
    const hasSettings = Object.keys(settingsPatch).length > 0
    const hasData = Object.keys(dataPatch).length > 0
    const hasColumns = Object.keys(columns).length > 0

    if (!hasSettings && !hasData && !hasColumns) {
      this.pendingChanges.clear()
      this.isSaving = false
      this.updateStatus("saved")
      return
    }

    try {
      const result = await this.savePatch(this.urlValue, settingsPatch, dataPatch, columns)
      this.applyServerResource(result?.[this.resourceKeyValue])

      // Clear pending changes on success
      this.pendingChanges.clear()
      this.updateStatus("saved")

      // Update saved timestamp
      if (this.hasSavedAtTarget) {
        this.savedAtTarget.textContent = new Date().toLocaleTimeString()
      }

    } catch (error) {
      logger.error("Settings save failed:", error)
      this.updateStatus("error", error.message)
    } finally {
      this.isSaving = false
    }
  }

  async savePatch(url, settingsPatch, dataPatch, columns = {}, attemptedConflictRetry = false) {
    const response = await fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify({
        schema_version: this.schemaVersionValue,
        settings_version: this.settingsVersionValue,
        ...columns,
        ...(Object.keys(settingsPatch).length ? { settings: settingsPatch } : {}),
        ...(Object.keys(dataPatch).length ? { data: dataPatch } : {})
      })
    })

    const result = await response.json()

    if (response.status === 409 && result?.conflict === true && attemptedConflictRetry === false) {
      const nextVersion = result?.[this.resourceKeyValue]?.settings_version
      if (typeof nextVersion === "number") {
        this.settingsVersionValue = nextVersion
        return this.savePatch(url, settingsPatch, dataPatch, columns, true)
      }
    }

    if (!response.ok || !result.ok) {
      throw new Error(result.errors?.join(", ") || "Save failed")
    }

    const resource = result?.[this.resourceKeyValue]
    if (typeof resource?.settings_version === "number") {
      this.settingsVersionValue = resource.settings_version
    }

    this.dispatch("saved", { detail: { key: this.resourceKeyValue, resource, result } })

    if (this.resourceKeyValue === "participant" && result?.participant) {
      this.dispatch("participantUpdated", { detail: { participant: result.participant } })
    }

    if (this.resourceKeyValue === "space_membership" && result?.space_membership) {
      this.dispatch("spaceMembershipUpdated", { detail: { space_membership: result.space_membership } })
    }

    return result
  }

  applyServerResource(resource) {
    if (!resource || typeof resource !== "object") return

    if (resource.settings && typeof resource.settings === "object") {
      this.syncSettingInputsFromSettings(resource.settings)
    }

    const schemaRenderer = this.application?.getControllerForElementAndIdentifier(this.element, "schema-renderer")
    schemaRenderer?.applyVisibility?.()
  }

  syncSettingInputsFromSettings(settings) {
    const inputs = Array.from(this.element.querySelectorAll("[data-setting-path^='settings.']"))

    inputs.forEach((input) => {
      const type = input.dataset.settingType
      if (type === "array" || type === "json") return

      const fullPath = input.dataset.settingPath
      if (!fullPath) return

      const dotted = fullPath.replace(/^settings\./, "")
      const value = this.digValue(settings, dotted)
      if (value === undefined) return

      this.setInputValueFromResource(input, value)
    })
  }

  digValue(root, dottedPath) {
    if (!root || typeof root !== "object") return undefined

    const parts = dottedPath.split(".").filter(Boolean)
    let current = root

    for (const part of parts) {
      if (!current || typeof current !== "object") return undefined
      if (!Object.prototype.hasOwnProperty.call(current, part)) return undefined
      current = current[part]
    }

    return current
  }

  setInputValueFromResource(input, value) {
    if (input.type === "checkbox") {
      input.checked = value === true
      return
    }

    if (value === null || value === undefined) {
      input.value = ""
      return
    }

    input.value = String(value)
  }

  getInputValue(input, type) {
    if (input.type === "checkbox") {
      return input.checked
    }

    const rawValue = input.value

    switch (type) {
      case "number":
        return input.type === "range" ? parseFloat(rawValue) : (rawValue === "" ? null : parseFloat(rawValue))
      case "integer":
        return input.type === "range" ? parseInt(rawValue, 10) : (rawValue === "" ? null : parseInt(rawValue, 10))
      case "boolean":
        return rawValue === "true" || rawValue === "1"
      case "array":
      case "json":
        try {
          return JSON.parse(rawValue)
        } catch {
          return rawValue
        }
      default:
        return rawValue
    }
  }

  assignNested(root, dottedPath, value) {
    const parts = dottedPath.split(".").filter(Boolean)
    if (parts.length === 0) return

    let current = root

    for (let i = 0; i < parts.length - 1; i++) {
      const segment = parts[i]
      if (typeof current[segment] !== "object" || current[segment] === null || Array.isArray(current[segment])) {
        current[segment] = {}
      }
      current = current[segment]
    }

    current[parts[parts.length - 1]] = value
  }

  updateStatus(status, message = null) {
    if (!this.hasStatusTarget) return

    const statusEl = this.statusTarget

    // Remove all status classes
    statusEl.classList.remove("badge-warning", "badge-info", "badge-success", "badge-error")

    switch (status) {
      case "pending":
        statusEl.classList.add("badge-warning")
        statusEl.textContent = "Unsaved"
        break
      case "saving":
        statusEl.classList.add("badge-info")
        statusEl.textContent = "Saving..."
        break
      case "saved":
        statusEl.classList.add("badge-success")
        statusEl.textContent = "Saved"
        // Auto-hide after 2 seconds
        setTimeout(() => {
          if (this.pendingChanges.size === 0) {
            statusEl.textContent = ""
            statusEl.classList.remove("badge-success")
          }
        }, 2000)
        break
      case "error":
        statusEl.classList.add("badge-error")
        statusEl.textContent = message || "Error"
        break
    }
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
