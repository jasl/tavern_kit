import { Controller } from "@hotwired/stimulus"

/**
 * Sidebar Controller
 *
 * Manages drawer sidebar state with localStorage persistence.
 * Supports keyboard shortcuts for quick toggling.
 */
export default class extends Controller {
  static targets = ["toggle"]
  static values = {
    key: { type: String, default: "sidebar" }
  }

  connect() {
    this.loadState()
    this.bindKeyboardShortcuts()
  }

  disconnect() {
    this.unbindKeyboardShortcuts()
  }

  toggle() {
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = !this.toggleTarget.checked
      this.saveState()
    }
  }

  open() {
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = true
      this.saveState()
    }
  }

  close() {
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = false
      this.saveState()
    }
  }

  // Private methods

  loadState() {
    if (!this.hasToggleTarget) return

    const storageKey = this.storageKey
    const savedState = localStorage.getItem(storageKey)

    // Only apply saved state on larger screens where sidebar is not always visible
    if (savedState !== null && this.shouldPersistState()) {
      this.toggleTarget.checked = savedState === "open"
    }
  }

  saveState() {
    if (!this.hasToggleTarget) return

    const storageKey = this.storageKey
    const state = this.toggleTarget.checked ? "open" : "closed"
    localStorage.setItem(storageKey, state)
  }

  get storageKey() {
    return `sidebar-${this.keyValue}`
  }

  shouldPersistState() {
    // Don't persist state on mobile where drawer behavior is different
    return window.innerWidth >= 1024 // lg breakpoint
  }

  bindKeyboardShortcuts() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  unbindKeyboardShortcuts() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    // Don't trigger if user is typing in an input
    if (event.target.matches("input, textarea, select, [contenteditable]")) {
      return
    }

    // [ for left sidebar, ] for right sidebar
    if (event.key === "[" && this.keyValue === "left") {
      event.preventDefault()
      this.toggle()
    } else if (event.key === "]" && this.keyValue === "right") {
      event.preventDefault()
      this.toggle()
    }
  }
}
