import { Controller } from "@hotwired/stimulus"

/**
 * Array Field Controller
 *
 * Manages dynamic array inputs for fields like alternate_greetings,
 * group_only_greetings, etc.
 *
 * Usage:
 * <div data-controller="array-field" data-array-field-name-value="character[data][alternate_greetings][]">
 *   <div data-array-field-target="list">
 *     <!-- Items rendered here -->
 *   </div>
 *   <template data-array-field-target="template">
 *     <div data-array-field-item>
 *       <textarea name="character[data][alternate_greetings][]"></textarea>
 *       <button type="button" data-action="array-field#remove">Remove</button>
 *     </div>
 *   </template>
 *   <div data-array-field-target="emptyState" class="hidden">No items</div>
 *   <button type="button" data-action="array-field#add">Add Item</button>
 * </div>
 */
export default class extends Controller {
  static targets = ["list", "template", "emptyState"]
  static values = { name: String }

  connect() {
    this.updateEmptyState()
  }

  /**
   * Add a new item to the array
   */
  add(event) {
    event.preventDefault()
    const fragment = this.templateTarget.content.cloneNode(true)
    this.listTarget.appendChild(fragment)
    this.updateEmptyState()

    // Focus the new input
    const newItem = this.listTarget.lastElementChild
    const input = newItem.querySelector("input, textarea")
    if (input) {
      input.focus()
    }
  }

  /**
   * Remove an item from the array
   */
  remove(event) {
    event.preventDefault()
    const item = event.target.closest("[data-array-field-item]")
    if (item) {
      item.remove()
      this.updateEmptyState()
    }
  }

  /**
   * Move an item up in the list
   */
  moveUp(event) {
    event.preventDefault()
    const item = event.target.closest("[data-array-field-item]")
    if (item && item.previousElementSibling) {
      item.parentNode.insertBefore(item, item.previousElementSibling)
    }
  }

  /**
   * Move an item down in the list
   */
  moveDown(event) {
    event.preventDefault()
    const item = event.target.closest("[data-array-field-item]")
    if (item && item.nextElementSibling) {
      item.parentNode.insertBefore(item.nextElementSibling, item)
    }
  }

  /**
   * Update the empty state visibility
   */
  updateEmptyState() {
    if (this.hasEmptyStateTarget) {
      const hasItems = this.listTarget.children.length > 0
      this.emptyStateTarget.classList.toggle("hidden", hasItems)
    }
  }
}
