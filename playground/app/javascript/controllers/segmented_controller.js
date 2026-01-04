import { Controller } from "@hotwired/stimulus"

/**
 * Segmented control controller for radio-button style selection.
 *
 * @example HTML structure
 *   <div data-controller="segmented">
 *     <input type="radio" data-segmented-target="option" data-action="change->segmented#select" value="a">
 *     <input type="radio" data-segmented-target="option" data-action="change->segmented#select" value="b">
 *     <input type="hidden" data-segmented-target="hidden" value="a">
 *   </div>
 */
export default class extends Controller {
  static targets = ["option", "hidden"]

  select(event) {
    const value = event.currentTarget.value
    if (this.hasHiddenTarget) {
      this.hiddenTarget.value = value
      // Trigger change event for settings-form controller
      this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }
}
