import { Controller } from "@hotwired/stimulus"
import { applyPresetById } from "../ui/preset_selector/apply"
import { closeSaveModal, openSaveModal, toggleMode } from "../ui/preset_selector/modal"
import { savePreset } from "../ui/preset_selector/save"

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

    await applyPresetById(this, presetId)
  }

  /**
   * Open the save preset modal
   */
  openSaveModal() {
    openSaveModal(this)
  }

  /**
   * Close the save preset modal
   */
  closeSaveModal() {
    closeSaveModal(this)
  }

  /**
   * Toggle visibility of name field based on save mode
   */
  toggleMode() {
    toggleMode(this)
  }

  /**
   * Save the preset (update existing or create new)
   */
  async save() {
    await savePreset(this)
  }

}
