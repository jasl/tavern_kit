import { Controller } from "@hotwired/stimulus"
import logger from "../logger"

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
      logger.error("No run data found on element")
      return
    }

    let runData
    try {
      runData = JSON.parse(runDataJson)
    } catch (e) {
      logger.error("Failed to parse run data:", e)
      return
    }

    // Find the run detail modal and execute its showRun method
    const modal = document.getElementById("run_detail_modal")
    if (!modal) {
      logger.error("Run detail modal not found")
      return
    }

    // Get the Stimulus controller for the modal
    const modalController = this.application.getControllerForElementAndIdentifier(modal, "run-detail-modal")
    if (modalController) {
      modalController.showRun(runData)
    } else {
      logger.error("Run detail modal controller not found")
    }
  }
}
