import { Controller } from "@hotwired/stimulus"

/**
 * Range display controller for updating output text when range input changes.
 *
 * @example HTML structure
 *   <div data-controller="range-display">
 *     <output data-range-display-target="output">50</output>
 *     <input type="range" data-range-display-target="input"
 *            data-action="input->range-display#update">
 *   </div>
 */
export default class extends Controller {
  static targets = ["input", "output"]

  connect() {
    // Set initial value
    if (this.hasInputTarget && this.hasOutputTarget) {
      this.outputTarget.textContent = this.inputTarget.value
    }
  }

  update(event) {
    if (this.hasOutputTarget) {
      this.outputTarget.textContent = event.currentTarget.value
    }
  }
}
