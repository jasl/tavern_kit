import { Controller } from "@hotwired/stimulus"

/**
 * Range display controller for range inputs.
 *
 * Supports two patterns:
 *
 * 1) Slider + output (read-only display):
 *   <fieldset data-controller="range-display">
 *     <output data-range-display-target="output">50</output>
 *     <input type="range" data-range-display-target="input"
 *            data-action="input->range-display#update">
 *   </fieldset>
 *
 * 2) Slider + number input (editable display):
 *   <fieldset data-controller="range-display">
 *     <input type="range" data-range-display-target="slider"
 *            data-action="input->range-display#updateFromSlider">
 *     <input type="number" data-range-display-target="number"
 *            data-action="input->range-display#updateFromNumber blur->range-display#validateOnBlur">
 *   </fieldset>
 *
 */
export default class extends Controller {
  static targets = ["input", "output", "slider", "number"]

  connect() {
    // Pattern 1: slider + output
    if (this.hasInputTarget && this.hasOutputTarget) {
      this.outputTarget.textContent = this.inputTarget.value
    }

    // Pattern 2: slider + number input
    if (this.hasSliderTarget && this.hasNumberTarget) {
      this.numberTarget.value = this.sliderTarget.value
      this.lastValidValue = parseFloat(this.sliderTarget.value)
    }
  }

  /**
   * Pattern 1: called when the slider changes - update output text.
   */
  update(event) {
    if (!this.hasOutputTarget) return
    this.outputTarget.textContent = event.currentTarget.value
  }

  /**
   * Called when the slider changes - update the number input
   */
  updateFromSlider(event) {
    if (this.hasNumberTarget) {
      const value = parseFloat(event.currentTarget.value)
      this.numberTarget.value = value
      this.lastValidValue = value
      // Dispatch input event on number input to trigger settings-form auto-save
      this.numberTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  /**
   * Check if the current value is valid
   */
  isValidValue(input) {
    const value = parseFloat(input.value)
    return !isNaN(value) && input.value.trim() !== ""
  }

  /**
   * Called when the number input changes - update the slider
   */
  updateFromNumber(event) {
    if (!this.hasSliderTarget) return

    // If invalid, don't update slider but let the autosave logic handle skipping
    if (!this.isValidValue(event.currentTarget)) {
      return
    }

    const value = parseFloat(event.currentTarget.value)
    const min = parseFloat(this.sliderTarget.min)
    const max = parseFloat(this.sliderTarget.max)

    // Clamp value to min/max range
    const clampedValue = Math.min(Math.max(value, min), max)

    // Update slider
    this.sliderTarget.value = clampedValue

    // Update number input if value was clamped
    if (value !== clampedValue) {
      event.currentTarget.value = clampedValue
    }

    // Store as last valid value
    this.lastValidValue = clampedValue
  }

  /**
   * Called when the number input loses focus - restore last valid value if current is invalid
   */
  validateOnBlur(event) {
    const input = event.currentTarget
    // If current value is invalid, restore last valid value
    if (!this.isValidValue(input)) {
      // Use setTimeout(0) to defer the value restoration until after the browser's
      // internal validation cycle completes, ensuring the visual display updates
      setTimeout(() => {
        input.value = this.lastValidValue
        if (this.hasSliderTarget) {
          this.sliderTarget.value = this.lastValidValue
        }
      }, 0)
    }
  }
}
