import { Controller } from "@hotwired/stimulus"

/**
 * Policy Preset Controller
 *
 * Provides one-click presets for scheduling policy configuration.
 * Updates both the policy select and debounce input when a preset is clicked.
 *
 * Presets:
 * - SillyTavern Classic: reject + 0ms (lock input during generation)
 * - Smart Turn Merge: queue + 800ms (merge rapid messages)
 * - ChatGPT-like: restart + 0ms (interrupt on new input)
 *
 * @example HTML structure
 *   <div data-controller="policy-preset">
 *     <button data-action="click->policy-preset#selectPreset"
 *             data-preset="sillytavern">SillyTavern Classic</button>
 *     <select data-policy-preset-target="policy">...</select>
 *     <input data-policy-preset-target="debounce" type="number">
 *   </div>
 */
export default class extends Controller {
  static targets = ["policy", "debounce", "presetButton"]

  static presets = {
    sillytavern: { policy: "reject", debounce: 0 },
    smartmerge: { policy: "queue", debounce: 800 },
    chatgpt: { policy: "restart", debounce: 0 }
  }

  connect() {
    this.updateActivePreset()
  }

  /**
   * Select a preset and update both policy and debounce fields.
   */
  selectPreset(event) {
    event.preventDefault()
    const presetName = event.currentTarget.dataset.preset
    const preset = this.constructor.presets[presetName]

    if (!preset) return

    // Update the form fields
    if (this.hasPolicyTarget) {
      this.policyTarget.value = preset.policy
      // Dispatch change event so Rails form knows it changed
      this.policyTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }

    if (this.hasDebounceTarget) {
      this.debounceTarget.value = preset.debounce
      // Dispatch input event so Rails form knows it changed
      this.debounceTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }

    this.updateActivePreset()
  }

  /**
   * Update the active state of preset buttons based on current values.
   */
  updateActivePreset() {
    if (!this.hasPolicyTarget || !this.hasDebounceTarget) return

    const currentPolicy = this.policyTarget.value
    const currentDebounce = parseInt(this.debounceTarget.value, 10) || 0

    // Find which preset (if any) matches current values
    let activePreset = null
    for (const [name, preset] of Object.entries(this.constructor.presets)) {
      if (preset.policy === currentPolicy && preset.debounce === currentDebounce) {
        activePreset = name
        break
      }
    }

    // Update button states
    this.presetButtonTargets.forEach((button) => {
      const isActive = button.dataset.preset === activePreset
      button.classList.toggle("btn-primary", isActive)
      button.classList.toggle("btn-outline", !isActive)
    })
  }

  /**
   * Called when policy select changes - update active preset indicator.
   */
  policyChanged() {
    this.updateActivePreset()
  }

  /**
   * Called when debounce input changes - update active preset indicator.
   */
  debounceChanged() {
    this.updateActivePreset()
  }
}
