import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { showToast, turboRequest } from "../request_helpers"

/**
 * Preset Selector Controller
 *
 * Manages preset selection and saving in the right sidebar.
 * - Apply preset when selected from dropdown
 * - Open save modal with update/create options
 * - Handle save operations via API
 */
export default class extends Controller {
  static targets = [
    "dropdown",
    "modal",
    "modeUpdate",
    "modeCreate",
    "nameField",
    "nameInput",
    "currentName"
  ]

  static values = {
    applyUrl: String,
    membershipId: Number,
    currentPresetId: Number
  }

  /**
   * Apply preset from dropdown menu click
   */
  async applyPreset(event) {
    event.preventDefault()
    const presetId = event.currentTarget.dataset.presetId
    if (!presetId) return

    // Update current preset ID
    this.currentPresetIdValue = presetId

    await this.#applyPresetById(presetId)
  }

  /**
   * Apply preset by ID
   */
  async #applyPresetById(presetId) {
    const formData = new FormData()
    formData.append("preset_id", presetId)
    formData.append("membership_id", this.membershipIdValue)

    await this.#sendRequest(this.applyUrlValue, "POST", formData)
  }

  /**
   * Open the save preset modal
   */
  openSaveModal() {
    if (!this.hasModalTarget) return

    // Reset to update mode
    if (this.hasModeUpdateTarget) {
      this.modeUpdateTarget.checked = true
    }
    this.toggleMode()
    this.modalTarget.showModal()
  }

  /**
   * Close the save preset modal
   */
  closeSaveModal() {
    this.hasModalTarget && this.modalTarget.close()
  }

  /**
   * Toggle visibility of name field based on save mode
   */
  toggleMode() {
    const isCreateMode = this.hasModeCreateTarget && this.modeCreateTarget.checked

    if (this.hasNameFieldTarget) {
      this.nameFieldTarget.classList.toggle("hidden", !isCreateMode)
    }

    // Clear name input when switching to update mode
    if (this.hasNameInputTarget && !isCreateMode) {
      this.nameInputTarget.value = ""
    }
  }

  /**
   * Save the preset (update existing or create new)
   */
  async save() {
    const isCreateMode = this.hasModeCreateTarget && this.modeCreateTarget.checked
    isCreateMode ? await this.#createPreset() : await this.#updatePreset()
  }

  // Private methods

  /**
   * Create a new preset from current settings
   */
  async #createPreset() {
    const name = this.hasNameInputTarget ? this.nameInputTarget.value.trim() : ""

    if (!name) {
      showToast("Please enter a preset name", "warning")
      if (this.hasNameInputTarget) this.nameInputTarget.focus()
      return
    }

    const formData = new FormData()
    formData.append("preset[name]", name)
    formData.append("preset[membership_id]", this.membershipIdValue)

    const success = await this.#sendRequest("/presets", "POST", formData)
    if (success) this.closeSaveModal()
  }

  /**
   * Update the currently selected preset with current settings
   */
  async #updatePreset() {
    const presetId = this.currentPresetIdValue

    if (!presetId) {
      showToast("No preset selected", "warning")
      return
    }

    const formData = new FormData()
    formData.append("membership_id", this.membershipIdValue)

    const success = await this.#sendRequest(`/presets/${presetId}`, "PATCH", formData)
    if (success) this.closeSaveModal()
  }

  /**
   * Send request and handle turbo stream response
   * @param {string} url - The request URL
   * @param {string} method - HTTP method (POST, PATCH, etc.)
   * @param {FormData} formData - Form data to send
   * @returns {Promise<boolean>} - Whether the request was successful
   */
  async #sendRequest(url, method, formData) {
    try {
      const { response, renderedTurboStream } = await turboRequest(url, {
        method,
        accept: "text/vnd.turbo-stream.html, text/html, application/json",
        body: formData
      })

      if (response.ok) {
        if (!renderedTurboStream) {
          window.location.reload()
        }
        return true
      }

      if (renderedTurboStream) return false

      await this.#handleErrorResponse(response)
      return false
    } catch (error) {
      logger.error("Request failed:", error)
      showToast("Request failed. Please try again.", "error")
      return false
    }
  }

  /**
   * Handle error response
   */
  async #handleErrorResponse(response) {
    try {
      const data = await response.json()
      showToast(data.error || data.errors?.join(", ") || "Request failed", "error")
    } catch {
      showToast("Request failed", "error")
    }
  }

}
