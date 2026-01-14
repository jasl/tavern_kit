import { Controller } from "@hotwired/stimulus"
import { connect, disconnect } from "../ui/character_picker/bindings"
import { handleFrameLoad } from "../ui/character_picker/frame_load"
import { updateFilterLinks } from "../ui/character_picker/links"
import { updateCardIndicator, updateCounter, updateHiddenInputs } from "../ui/character_picker/ui_sync"

/**
 * Character Picker Controller
 *
 * Manages character selection state across Turbo Frame reloads.
 * Persists selected IDs and syncs visual state after frame updates.
 */
export default class extends Controller {
  static targets = ["card", "checkbox", "hiddenInputs", "counter", "grid"]
  static values = {
    selected: { type: Array, default: [] },
    fieldName: { type: String, default: "character_ids[]" }
  }

  connect() {
    connect(this)
  }

  disconnect() {
    disconnect(this)
  }

  /**
   * Handle Turbo Frame load - re-sync checkboxes after frame update
   */
  handleFrameLoad(_event) {
    handleFrameLoad(this)
  }

  /**
   * Handle checkbox toggle
   */
  toggle(event) {
    const checkbox = event.target
    const characterId = parseInt(checkbox.value, 10)
    const card = checkbox.closest("[data-character-picker-target='card']")

    if (checkbox.checked) {
      // Add to selection
      if (!this.selectedValue.includes(characterId)) {
        this.selectedValue = [...this.selectedValue, characterId]
      }
      card?.classList.remove("border-transparent", "hover:border-base-300")
      card?.classList.add("border-primary", "bg-primary/5")
      updateCardIndicator(card, true)
    } else {
      // Remove from selection
      this.selectedValue = this.selectedValue.filter(id => id !== characterId)
      card?.classList.remove("border-primary", "bg-primary/5")
      card?.classList.add("border-transparent", "hover:border-base-300")
      updateCardIndicator(card, false)
    }

    updateCounter(this)
    updateHiddenInputs(this)
  }

  /**
   * Called when the selected value changes
   */
  selectedValueChanged() {
    // Update params in filter links to preserve selection across pagination
    updateFilterLinks(this)
  }
}
