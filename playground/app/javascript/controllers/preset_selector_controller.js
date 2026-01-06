import { Controller } from "@hotwired/stimulus"

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
    "select",
    "modal",
    "modeUpdate",
    "modeCreate",
    "nameField",
    "nameInput",
    "currentName"
  ]

  static values = {
    applyUrl: String,
    membershipId: Number
  }

  /**
   * Apply selected preset to the current membership
   */
  async apply(event) {
    const presetId = event.target.value
    if (!presetId) return

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
      alert("Please enter a preset name")
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
    const presetId = this.hasSelectTarget ? this.selectTarget.value : null

    if (!presetId) {
      alert("No preset selected")
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
      const response = await fetch(url, {
        method,
        headers: {
          "X-CSRF-Token": this.#csrfToken,
          "Accept": "text/vnd.turbo-stream.html, text/html, application/json"
        },
        body: formData
      })

      if (response.ok) {
        await this.#handleSuccessResponse(response)
        return true
      } else {
        await this.#handleErrorResponse(response)
        return false
      }
    } catch (error) {
      console.error("Request failed:", error)
      alert("Request failed. Please try again.")
      return false
    }
  }

  /**
   * Handle successful response (turbo stream or reload)
   */
  async #handleSuccessResponse(response) {
    const contentType = response.headers.get("content-type")
    if (contentType?.includes("turbo-stream")) {
      const html = await response.text()
      Turbo.renderStreamMessage(html)
    } else {
      window.location.reload()
    }
  }

  /**
   * Handle error response
   */
  async #handleErrorResponse(response) {
    try {
      const data = await response.json()
      alert(data.error || data.errors?.join(", ") || "Request failed")
    } catch {
      alert("Request failed")
    }
  }

  /**
   * Get CSRF token from meta tag
   */
  get #csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
