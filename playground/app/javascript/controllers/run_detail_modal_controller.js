import { Controller } from "@hotwired/stimulus"
import { showToast } from "../request_helpers"
import { copyTextToClipboard } from "../dom_helpers"
import { renderRunDetailModalContent } from "../ui/run_detail_modal/render"

/**
 * Run Detail Modal Controller
 *
 * Handles the debug modal for displaying conversation run details.
 * Shows run metadata, error payloads, and allows copying prompt JSON.
 *
 * The modal is opened by clicking a run item in the runs panel.
 * Run data is passed via data attributes on the clicked element.
 */
export default class extends Controller {
  static targets = ["content"]

  // Store current run data for copy functionality
  currentRunData = null

  /**
   * Open the modal and populate it with run data.
   *
   * @param {Object} runData - The run data object
   */
  showRun(runData) {
    this.currentRunData = runData
    this.renderContent(runData)
    this.element.showModal()
  }

  /**
   * Copy prompt snapshot JSON to clipboard.
   * Called by the Copy JSON button in the Prompt JSON tab.
   */
  async copyPromptJson() {
    if (!this.currentRunData?.prompt_snapshot) {
      showToast("No prompt snapshot available", "warning")
      return
    }

    const json = JSON.stringify(this.currentRunData.prompt_snapshot, null, 2)
    const ok = await copyTextToClipboard(json)
    showToast(ok ? "Copied to clipboard" : "Failed to copy", ok ? "success" : "error")
  }

  /**
   * Render the run details content with tabs.
   *
   * @param {Object} data - The run data
   */
  renderContent(data) {
    if (!this.hasContentTarget) return
    this.contentTarget.replaceChildren(renderRunDetailModalContent(data))
  }
}
