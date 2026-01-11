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

  /**
   * Open the sidebar and switch to a specific tab.
   *
   * Called via action: click->sidebar#openTab
   * Expects data-sidebar-tab-param="tabName"
   *
   * @param {Event} event - Click event with tab param
   */
  openTab(event) {
    const tabName = event.params?.tab
    if (!tabName) return

    // Open the sidebar first
    this.open()

    // Find the tabs controller within this sidebar and select the tab
    // We need a small delay to ensure the drawer is visible before switching tabs
    requestAnimationFrame(() => {
      const tabsElement = this.element.querySelector("[data-controller~='tabs']")
      if (tabsElement) {
        const tabButton = tabsElement.querySelector(`[data-tab="${tabName}"]`)
        if (tabButton) {
          tabButton.click()
        }
      }
    })
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
    // Don't trigger if user is typing in an input field
    // Exception: Allow [ and ] if the chat textarea (message_content) is empty
    if (event.target.matches("input, textarea, select, [contenteditable]")) {
      // Allow sidebar toggle if:
      // 1. It's the chat message textarea (id="message_content")
      // 2. The textarea is empty
      // 3. The key is [ or ]
      const isChatTextarea = event.target.id === "message_content"
      const isTextareaEmpty = event.target.value?.trim().length === 0
      const isSidebarKey = event.key === "[" || event.key === "]"

      if (!(isChatTextarea && isTextareaEmpty && isSidebarKey)) {
        return
      }
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
