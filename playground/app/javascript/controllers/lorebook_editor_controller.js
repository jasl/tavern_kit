import { Controller } from "@hotwired/stimulus"

/**
 * Lorebook Editor Controller
 *
 * Main controller for the lorebook editing page.
 * Coordinates between entry list, forms, and modals.
 */
export default class extends Controller {
  connect() {
    // Register modal close handlers
    this.element.querySelectorAll("dialog").forEach(dialog => {
      dialog.addEventListener("close", () => {
        // Reset form on close if needed
      })
    })
  }

  openNewEntry() {
    const modal = document.getElementById("new_entry_modal")
    if (modal) {
      modal.showModal()
    }
  }

  closeAllModals() {
    this.element.querySelectorAll("dialog[open]").forEach(dialog => {
      dialog.close()
    })
  }
}
