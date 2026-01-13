import { Controller } from "@hotwired/stimulus"

/**
 * Character Picker Controller
 *
 * Manages character selection state across Turbo Frame reloads.
 * Persists selected IDs and syncs visual state after frame updates.
 */
export default class extends Controller {
  static targets = ["card", "checkbox", "hiddenInputs", "counter", "grid"]
  static values = {
    selected: { type: Array, default: [] },
    fieldName: { type: String, default: "character_ids[]" }
  }

  connect() {
    // Store bound function reference for proper cleanup
    this.boundHandleFrameLoad = this.handleFrameLoad.bind(this)

    // Listen for Turbo Frame load events to re-sync state
    this.element.addEventListener("turbo:frame-load", this.boundHandleFrameLoad)
    
    // Initial sync
    this.syncCheckboxes()
    this.updateCounter()
    this.updateHiddenInputs()
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this.boundHandleFrameLoad)
  }

  /**
   * Handle Turbo Frame load - re-sync checkboxes after frame update
   */
  handleFrameLoad(_event) {
    // Re-sync after small delay to ensure DOM is updated
    requestAnimationFrame(() => {
      this.syncCheckboxes()
      this.updateCounter()
      this.updateFilterLinks()
    })
  }

  /**
   * Handle checkbox toggle
   */
  toggle(event) {
    const checkbox = event.target
    const characterId = parseInt(checkbox.value, 10)
    const card = checkbox.closest("[data-character-picker-target='card']")

    if (checkbox.checked) {
      // Add to selection
      if (!this.selectedValue.includes(characterId)) {
        this.selectedValue = [...this.selectedValue, characterId]
      }
      card?.classList.remove("border-transparent", "hover:border-base-300")
      card?.classList.add("border-primary", "bg-primary/5")
      this.updateCardIndicator(card, true)
    } else {
      // Remove from selection
      this.selectedValue = this.selectedValue.filter(id => id !== characterId)
      card?.classList.remove("border-primary", "bg-primary/5")
      card?.classList.add("border-transparent", "hover:border-base-300")
      this.updateCardIndicator(card, false)
    }

    this.updateCounter()
    this.updateHiddenInputs()
  }

  /**
   * Update the selection indicator icon on a card
   */
  updateCardIndicator(card, selected) {
    const indicator = card?.querySelector(".absolute.top-1.right-1 div")
    const icon = indicator?.querySelector("span")

    if (indicator && icon) {
      if (selected) {
        indicator.classList.remove("bg-base-300/80", "text-base-content/50")
        indicator.classList.add("bg-primary", "text-primary-content")
        icon.classList.remove("icon-[lucide--plus]")
        icon.classList.add("icon-[lucide--check]")
      } else {
        indicator.classList.remove("bg-primary", "text-primary-content")
        indicator.classList.add("bg-base-300/80", "text-base-content/50")
        icon.classList.remove("icon-[lucide--check]")
        icon.classList.add("icon-[lucide--plus]")
      }
    }
  }

  /**
   * Sync all checkboxes with the current selected values
   * Called after Turbo Frame updates to restore state
   */
  syncCheckboxes() {
    this.checkboxTargets.forEach(checkbox => {
      const characterId = parseInt(checkbox.value, 10)
      const shouldBeSelected = this.selectedValue.includes(characterId)
      const card = checkbox.closest("[data-character-picker-target='card']")

      checkbox.checked = shouldBeSelected

      if (shouldBeSelected) {
        card?.classList.remove("border-transparent", "hover:border-base-300")
        card?.classList.add("border-primary", "bg-primary/5")
        this.updateCardIndicator(card, true)
      } else {
        card?.classList.remove("border-primary", "bg-primary/5")
        card?.classList.add("border-transparent", "hover:border-base-300")
        this.updateCardIndicator(card, false)
      }
    })
  }

  /**
   * Update the selection counter badge
   */
  updateCounter() {
    if (!this.hasCounterTarget) return
    
    const count = this.selectedValue.length
    this.counterTarget.textContent = `${count} selected`
  }

  /**
   * Update hidden inputs to ensure form submission includes all selected IDs
   */
  updateHiddenInputs() {
    if (!this.hasHiddenInputsTarget) return

    // Create hidden inputs for all selected IDs
    const inputs = this.selectedValue.map(id => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = this.fieldNameValue
      input.value = id
      return input
    })

    // Replace all children at once (safer than innerHTML = "")
    this.hiddenInputsTarget.replaceChildren(...inputs)
  }

  /**
   * Called when the selected value changes
   */
  selectedValueChanged() {
    // Update params in filter links to preserve selection across pagination
    this.updateFilterLinks()
  }

  /**
   * Update filter links to include current selection
   */
  updateFilterLinks() {
    const links = this.element.querySelectorAll("a[data-turbo-frame='character_picker']")
    links.forEach(link => {
      const url = new URL(link.href)

      // Remove existing selected params
      url.searchParams.delete("selected[]")

      // Add current selection
      this.selectedValue.forEach(id => {
        url.searchParams.append("selected[]", id)
      })

      link.href = url.toString()
    })
  }
}
