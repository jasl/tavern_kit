import { Controller } from "@hotwired/stimulus"

/**
 * Dropdown Select Controller
 *
 * Handles dropdown menus that act like select inputs.
 * Updates the label when an option is selected and closes the dropdown.
 */
export default class extends Controller {
  static targets = ["label"]
  static values = {
    selected: String
  }

  /**
   * Handle option selection
   * Updates the label and closes the dropdown
   */
  select(event) {
    event.preventDefault()

    const name = event.currentTarget.dataset.presetName
    if (name && this.hasLabelTarget) {
      this.labelTarget.textContent = name
    }

    // Close dropdown by removing focus
    document.activeElement?.blur()
  }
}
