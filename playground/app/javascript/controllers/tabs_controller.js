import { Controller } from "@hotwired/stimulus"

/**
 * Generic tab switching controller.
 *
 * Manages tab navigation with optional URL state persistence.
 *
 * @example HTML structure
 *   <div data-controller="tabs" data-tabs-default-value="quick">
 *     <div role="tablist" class="tabs tabs-box">
 *       <button data-tabs-target="tab" data-tab="quick" data-action="click->tabs#select">Quick</button>
 *       <button data-tabs-target="tab" data-tab="advanced" data-action="click->tabs#select">Advanced</button>
 *     </div>
 *     <div data-tabs-target="panel" data-tab="quick">Quick content</div>
 *     <div data-tabs-target="panel" data-tab="advanced">Advanced content</div>
 *   </div>
 */
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = {
    default: { type: String, default: "" },
    current: { type: String, default: "" },
    persist: { type: Boolean, default: false },
    persistKey: { type: String, default: "" }
  }

  connect() {
    // Restore from URL or localStorage
    const restored = this.restoreTab()

    // Use restored tab, URL param, or default
    const initial = restored || this.defaultValue || this.tabTargets[0]?.dataset.tab
    if (initial) {
      this.select({ currentTarget: { dataset: { tab: initial } } })
    }
  }

  /**
   * Select a tab by name.
   * @param {Event|Object} event - Click event or object with currentTarget.dataset.tab
   */
  select(event) {
    const tabName = event.currentTarget?.dataset?.tab || event.detail?.tab

    if (!tabName) return

    this.currentValue = tabName

    // Update tab buttons
    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.tab === tabName
      tab.classList.toggle("tab-active", isActive)
      tab.setAttribute("aria-selected", isActive)
    })

    // Update panels
    this.panelTargets.forEach(panel => {
      const isActive = panel.dataset.tab === tabName
      panel.classList.toggle("hidden", !isActive)
      panel.setAttribute("aria-hidden", !isActive)
    })

    // Persist if enabled
    if (this.persistValue) {
      this.persistTab(tabName)
    }

    // Dispatch custom event
    this.dispatch("changed", { detail: { tab: tabName } })
  }

  /**
   * Select next tab.
   */
  next() {
    const tabs = this.tabTargets.map(t => t.dataset.tab)
    const currentIndex = tabs.indexOf(this.currentValue)
    const nextIndex = (currentIndex + 1) % tabs.length
    this.select({ currentTarget: { dataset: { tab: tabs[nextIndex] } } })
  }

  /**
   * Select previous tab.
   */
  previous() {
    const tabs = this.tabTargets.map(t => t.dataset.tab)
    const currentIndex = tabs.indexOf(this.currentValue)
    const prevIndex = (currentIndex - 1 + tabs.length) % tabs.length
    this.select({ currentTarget: { dataset: { tab: tabs[prevIndex] } } })
  }

  // Private methods

  restoreTab() {
    if (!this.persistValue) return null

    const key = this.persistKeyValue || `tabs_${this.element.id}`

    // Check URL params first
    const urlParams = new URLSearchParams(window.location.search)
    const urlTab = urlParams.get(key)
    if (urlTab && this.isValidTab(urlTab)) return urlTab

    // Fall back to localStorage
    const stored = localStorage.getItem(key)
    if (stored && this.isValidTab(stored)) return stored

    return null
  }

  persistTab(tabName) {
    const key = this.persistKeyValue || `tabs_${this.element.id}`
    localStorage.setItem(key, tabName)
  }

  isValidTab(tabName) {
    return this.tabTargets.some(t => t.dataset.tab === tabName)
  }
}
