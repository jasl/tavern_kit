import { Controller } from "@hotwired/stimulus"
import { jsonRequest } from "../request_helpers"
import { buildLayoutFromSchema } from "../ui/schema_renderer/layout"
import { renderForTab as renderForTabImpl } from "../ui/schema_renderer/render"
import {
  applyVisibility as applyVisibilityImpl,
  scheduleVisibilityUpdate as scheduleVisibilityUpdateRaf
} from "../ui/schema_renderer/visibility"

/**
 * Schema-driven layout controller (no field generation).
 *
 * This controller only uses x-ui layout hints already embedded as data-* on
 * server-rendered fields:
 * - data-ui-group
 * - data-ui-order
 * - data-ui-tab (basic, prompts, authors_note, more)
 * - data-visible-when (x-ui.visibleWhen)
 */
export default class extends Controller {
  static targets = ["pool", "basic", "prompts", "authors_note", "more"]
  static values = {
    schemaUrl: String,
    context: Object
  }

  // All known tab names
  static TABS = ["basic", "prompts", "authors_note", "more"]

  fields = []
  layout = null
  schema = null
  visibilityRaf = null

  async connect() {
    this.fields = Array.from(this.poolTarget.querySelectorAll("[data-schema-field='true']"))

    if (this.schemaUrlValue) {
      try {
        const { response, data } = await jsonRequest(this.schemaUrlValue)
        if (response.ok && data) {
          this.schema = data
          this.layout = buildLayoutFromSchema(data, this.fields)
        }
      } catch {
        // Schema fetch is best-effort; layout uses embedded data attributes.
      }
    }

    this.element.addEventListener("change", this.scheduleVisibilityUpdate)
    this.element.addEventListener("input", this.scheduleVisibilityUpdate)

    // Render for currently active tab (check which panel is visible, or default to "basic")
    const activeTab = this.getActiveTab()
    this.renderForTab(activeTab)
  }

  /**
   * Determine which tab is currently active by checking panel visibility.
   * The panels have data-tabs-target="panel" and the hidden class is on the panel, not on our targets.
   * Falls back to "basic" if no active tab is found.
   * @returns {string}
   */
  getActiveTab() {
    // Find the panel elements (parent of our targets) and check which one is visible
    const panels = this.element.querySelectorAll("[data-tabs-target='panel']")
    for (const panel of panels) {
      if (!panel.classList.contains("hidden")) {
        const tabName = panel.dataset.tab
        // Only return for known schema tabs
        if (this.constructor.TABS.includes(tabName)) {
          return tabName
        }
      }
    }
    return "basic"
  }

  disconnect() {
    this.element.removeEventListener("change", this.scheduleVisibilityUpdate)
    this.element.removeEventListener("input", this.scheduleVisibilityUpdate)

    if (this.visibilityRaf) {
      cancelAnimationFrame(this.visibilityRaf)
      this.visibilityRaf = null
    }
  }

  scheduleVisibilityUpdate = () => {
    scheduleVisibilityUpdateRaf(this)
  }

  tabChanged(event) {
    const tab = event?.detail?.tab
    if (!tab) return

    this.renderForTab(tab)
  }

  participantUpdated(event) {
    const participant = event?.detail?.participant
    if (!participant) return

    // Important: provider_identification may legitimately be null when no effective provider exists.
    // We still need to update context so visibility rules can turn off cleanly (avoid stale gating).
    if (!Object.prototype.hasOwnProperty.call(participant, "provider_identification")) return

    this.setContext({ provider_identification: participant.provider_identification })
  }

  spaceMembershipUpdated(event) {
    const spaceMembership = event?.detail?.space_membership
    if (!spaceMembership) return

    // Important: provider_identification may legitimately be null when no effective provider exists.
    // We still need to update context so visibility rules can turn off cleanly (avoid stale gating).
    if (!Object.prototype.hasOwnProperty.call(spaceMembership, "provider_identification")) return

    this.setContext({ provider_identification: spaceMembership.provider_identification })
  }

  setContext(next) {
    this.contextValue = { ...(this.contextValue || {}), ...(next || {}) }
    this.applyVisibility()
  }

  applyVisibility() {
    applyVisibilityImpl(this)
  }

  renderForTab(tab) {
    renderForTabImpl(this, tab)
  }
}
