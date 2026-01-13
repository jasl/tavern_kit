import { Controller } from "@hotwired/stimulus"

/**
 * Sortable Controller
 *
 * Enables drag-and-drop reordering of list items.
 * Uses native HTML5 drag and drop API.
 */
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.setupDragHandlers()
  }

  setupDragHandlers() {
    const items = this.element.querySelectorAll("[data-sortable-item]")

    items.forEach(item => {
      const handle = item.querySelector("[data-sortable-handle]")
      const dragTarget = handle || item

      dragTarget.setAttribute("draggable", "true")

      dragTarget.addEventListener("dragstart", this.handleDragStart.bind(this, item))
      item.addEventListener("dragover", this.handleDragOver.bind(this))
      item.addEventListener("drop", this.handleDrop.bind(this))
      item.addEventListener("dragend", this.handleDragEnd.bind(this))
    })
  }

  handleDragStart(item, event) {
    this.draggedItem = item
    item.classList.add("opacity-50")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", item.dataset.entryId || item.id)
  }

  handleDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    const item = event.target.closest("[data-sortable-item]")
    if (!item || item === this.draggedItem) return

    const rect = item.getBoundingClientRect()
    const midpoint = rect.top + rect.height / 2

    if (event.clientY < midpoint) {
      item.parentNode.insertBefore(this.draggedItem, item)
    } else {
      item.parentNode.insertBefore(this.draggedItem, item.nextSibling)
    }
  }

  handleDrop(event) {
    event.preventDefault()
    this.saveOrder()
  }

  handleDragEnd(_event) {
    if (this.draggedItem) {
      this.draggedItem.classList.remove("opacity-50")
      this.draggedItem = null
    }
  }

  saveOrder() {
    if (!this.urlValue) return

    const items = this.element.querySelectorAll("[data-sortable-item]")
    const positions = Array.from(items).map(item => item.dataset.entryId || item.id.replace(/[^0-9]/g, ""))

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ positions })
    }).catch(error => console.error("Failed to save order:", error))
  }
}
