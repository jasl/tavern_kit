import { Controller } from "@hotwired/stimulus"

/**
 * Runs Panel Filter Controller
 *
 * Controls visibility of HumanTurn runs in the debug panel.
 * HumanTurn runs are hidden by default but can be shown for debugging.
 */
export default class extends Controller {
  static targets = ["toggle", "humanRun"]

  /**
   * Toggle visibility of human turn runs.
   */
  toggleFilter() {
    const showHumanTurns = this.toggleTarget.checked

    this.humanRunTargets.forEach(element => {
      if (showHumanTurns) {
        element.classList.remove("hidden")
      } else {
        element.classList.add("hidden")
      }
    })
  }
}
