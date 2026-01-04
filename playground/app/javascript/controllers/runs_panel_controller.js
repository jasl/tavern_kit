import { Controller } from "@hotwired/stimulus"

/**
 * Runs Panel Controller
 *
 * Handles click events on run items in the runs panel.
 * Opens the run detail modal with the clicked run's data.
 */
export default class extends Controller {
  /**
   * Handle click on a run item - open the detail modal.
   *
   * @param {Event} event - The click event
   */
  showRunDetail(event) {
    const button = event.currentTarget
    const runDataJson = button.dataset.runData

    if (!runDataJson) {
      console.error("No run data found on element")
      return
    }

    let runData
    try {
      runData = JSON.parse(runDataJson)
    } catch (e) {
      console.error("Failed to parse run data:", e)
      return
    }

    // Find the run detail modal and call its showRun method
    const modal = document.getElementById("run_detail_modal")
    if (!modal) {
      console.error("Run detail modal not found")
      return
    }

    // Get the Stimulus controller for the modal
    const modalController = this.application.getControllerForElementAndIdentifier(modal, "run-detail-modal")
    if (modalController) {
      modalController.showRun(runData)
    } else {
      console.error("Run detail modal controller not found")
    }
  }
}
