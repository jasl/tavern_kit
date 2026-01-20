import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { showToastIfNeeded, turboRequest, withRequestLock } from "../request_helpers"

/**
 * Sortable Controller
 *
 * Enables drag-and-drop reordering of list items.
 * Uses native HTML5 drag and drop API.
 */
export default class extends Controller {
  static values = { url: String, disabled: Boolean, handle: String }

  connect() {
    if (this.disabledValue) return

    this.draggedItem = null
    this.applyDraggableAttributes()
    this.bindEvents()
    this.observeMutations()
  }

  disconnect() {
    this.unbindEvents()

    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
  }

  bindEvents() {
    this._onDragStart = this.handleDragStart.bind(this)
    this._onDragOver = this.handleDragOver.bind(this)
    this._onDrop = this.handleDrop.bind(this)
    this._onDragEnd = this.handleDragEnd.bind(this)

    this.element.addEventListener("dragstart", this._onDragStart)
    this.element.addEventListener("dragover", this._onDragOver)
    this.element.addEventListener("drop", this._onDrop)
    this.element.addEventListener("dragend", this._onDragEnd)
  }

  unbindEvents() {
    if (!this._onDragStart) return

    this.element.removeEventListener("dragstart", this._onDragStart)
    this.element.removeEventListener("dragover", this._onDragOver)
    this.element.removeEventListener("drop", this._onDrop)
    this.element.removeEventListener("dragend", this._onDragEnd)

    this._onDragStart = null
    this._onDragOver = null
    this._onDrop = null
    this._onDragEnd = null
  }

  observeMutations() {
    // Turbo morph can preserve the controller element but replace its children.
    // When that happens we must re-apply draggable attributes to the new DOM.
    this.observer = new MutationObserver(() => this.applyDraggableAttributes())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  handleSelector() {
    const selector = this.hasHandleValue ? this.handleValue : ""
    return selector || "[data-sortable-handle]"
  }

  applyDraggableAttributes() {
    const items = this.element.querySelectorAll("[data-sortable-item]")
    const handleSelector = this.handleSelector()

    items.forEach(item => {
      const handle = handleSelector ? item.querySelector(handleSelector) : null
      const dragTarget = handle || item
      dragTarget.setAttribute("draggable", "true")
    })
  }

  handleDragStart(event) {
    const item = event.target.closest("[data-sortable-item]")
    if (!item) return

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
    void this.saveOrder()
  }

  handleDragEnd(_event) {
    if (this.draggedItem) {
      this.draggedItem.classList.remove("opacity-50")
      this.draggedItem = null
    }
  }

  async saveOrder() {
    if (!this.urlValue) return

    const items = this.element.querySelectorAll("[data-sortable-item]")
    const positions = Array.from(items).map(item => item.dataset.entryId || item.id.replace(/[^0-9]/g, ""))

    await withRequestLock(this.urlValue, async () => {
      try {
        const { response, toastAlreadyShown } = await turboRequest(this.urlValue, {
          method: "PATCH",
          body: { positions },
          headers: {
            Accept: "text/vnd.turbo-stream.html, application/json, text/html, application/xhtml+xml"
          }
        })

        if (!response.ok) {
          showToastIfNeeded(toastAlreadyShown, "Failed to save order.", "error", 3000)
        }
      } catch (error) {
        logger.error("Failed to save order:", error)
        showToastIfNeeded(false, "Failed to save order.", "error", 3000)
      }
    })
  }
}
