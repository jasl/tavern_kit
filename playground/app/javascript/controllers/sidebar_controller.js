import { Controller } from "@hotwired/stimulus"
import { bindKeyboardShortcuts, handleKeydown, unbindKeyboardShortcuts } from "../ui/sidebar/keyboard"
import { loadState, saveState } from "../ui/sidebar/storage"
import { openTab } from "../ui/sidebar/tabs"

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
    loadState(this)
    bindKeyboardShortcuts(this)
  }

  disconnect() {
    unbindKeyboardShortcuts(this)
  }

  toggle() {
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = !this.toggleTarget.checked
      saveState(this)
    }
  }

  open() {
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = true
      saveState(this)
    }
  }

  close() {
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = false
      saveState(this)
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
    openTab(this, tabName)
  }

  handleKeydown(event) {
    handleKeydown(this, event)
  }
}
