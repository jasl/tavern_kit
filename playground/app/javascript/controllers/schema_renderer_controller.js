import { Controller } from "@hotwired/stimulus"

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
        const response = await fetch(this.schemaUrlValue, { headers: { "Accept": "application/json" } })
        if (response.ok) {
          this.schema = await response.json()
          this.layout = this.buildLayoutFromSchema(this.schema)
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
    if (this.visibilityRaf) return

    this.visibilityRaf = requestAnimationFrame(() => {
      this.visibilityRaf = null
      this.applyVisibility()
    })
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

  // Private

  /**
   * Get the target element for a given tab name.
   * @param {string} tab
   * @returns {HTMLElement|null}
   */
  getTabTarget(tab) {
    switch (tab) {
      case "basic": return this.hasBasicTarget ? this.basicTarget : null
      case "prompts": return this.hasPromptsTarget ? this.promptsTarget : null
      case "authors_note": return this.hasAuthors_noteTarget ? this.authors_noteTarget : null
      case "more": return this.hasMoreTarget ? this.moreTarget : null
      default: return null
    }
  }

  renderForTab(tab) {
    // Move all fields back into the pool so we never duplicate nodes.
    this.fields.forEach((field) => this.poolTarget.appendChild(field))

    // Clear all tab targets
    this.constructor.TABS.forEach((tabName) => {
      const target = this.getTabTarget(tabName)
      if (target) target.innerHTML = ""
    })

    // Get the destination container
    const destination = this.getTabTarget(tab)
    if (!destination) return

    const items = this.layout || this.layoutFromDataAttributes()

    // Filter items for this tab
    const selected = items.filter((i) => i.uiTab === tab)

    const groups = this.groupItems(selected)
    groups.forEach(({ label, items }) => {
      const { container, content } = this.buildGroup(label, tab)
      items.forEach((i) => content.appendChild(i.element))
      destination.appendChild(container)
    })

    this.applyVisibility()
  }

  groupItems(items) {
    const byGroup = new Map()

    items.forEach((item) => {
      const label = item.uiGroup || "General"
      if (!byGroup.has(label)) byGroup.set(label, [])
      byGroup.get(label).push(item)
    })

    const groups = Array.from(byGroup.entries()).map(([label, groupItems]) => {
      groupItems.sort((a, b) => (a.uiOrder || 999) - (b.uiOrder || 999))
      return {
        label,
        order: groupItems.length ? Math.min(...groupItems.map((i) => i.uiOrder || 999)) : 999,
        items: groupItems
      }
    })

    groups.sort((a, b) => a.order - b.order)
    return groups
  }

  buildGroup(label, tab) {
    // Use flat layout for all tabs (no collapsible groups)
    const wrapper = document.createElement("div")
    wrapper.dataset.schemaGroup = "true"
    wrapper.className = "space-y-3"

    const header = document.createElement("div")
    header.className = "text-xs font-medium text-base-content/60 uppercase tracking-wide"
    header.textContent = label

    const content = document.createElement("div")
    content.className = "space-y-3"

    wrapper.appendChild(header)
    wrapper.appendChild(content)

    return { container: wrapper, content }
  }

  applyVisibility() {
    const context = this.contextValue || {}

    const items = this.layout || this.layoutFromDataAttributes()

    items.forEach((item) => {
      const rule = item.visibleWhen

      if (!rule) {
        this.showField(item.element)
        return
      }

      let shouldShow = true

      // Context gating (e.g., provider_identification)
      if (rule?.context && Object.prototype.hasOwnProperty.call(rule, "const")) {
        const ctxVal = context[rule.context]
        shouldShow = ctxVal === rule.const
      }

      // Ref gating (e.g., show join_prefix when generation_handling_mode in [...])
      if (shouldShow && rule?.ref) {
        const refValue = this.readValueForRef(rule.ref)
        if (Array.isArray(rule.in)) {
          shouldShow = rule.in.includes(refValue)
        } else if (Object.prototype.hasOwnProperty.call(rule, "const")) {
          shouldShow = refValue === rule.const
        }
      }

      if (shouldShow) {
        this.showField(item.element)
      } else {
        this.hideField(item.element)
      }
    })

    this.hideEmptyGroups()
  }

  showField(field) {
    field.classList.remove("hidden")
    field.removeAttribute("aria-hidden")

    field.querySelectorAll("input, select, textarea").forEach((el) => {
      if (el.dataset.schemaDisabled === "true") return
      // Only re-enable inputs that were disabled by `hideField` (visibility gating).
      if (el.dataset.visibilityDisabled === "true") {
        el.removeAttribute("disabled")
        delete el.dataset.visibilityDisabled
      }
    })
  }

  hideField(field) {
    field.classList.add("hidden")
    field.setAttribute("aria-hidden", "true")

    field.querySelectorAll("input, select, textarea").forEach((el) => {
      if (el.dataset.schemaDisabled === "true") return
      if (el.disabled) return

      el.setAttribute("disabled", "disabled")
      el.dataset.visibilityDisabled = "true"
    })
  }

  hideEmptyGroups() {
    this.constructor.TABS.forEach((tabName) => {
      const container = this.getTabTarget(tabName)
      if (!container) return

      container.querySelectorAll("[data-schema-group='true']").forEach((group) => {
        const visible = group.querySelectorAll("[data-schema-field='true']:not(.hidden)")
        group.classList.toggle("hidden", visible.length === 0)
      })
    })
  }

  layoutFromDataAttributes() {
    return this.fields.map((field) => ({
      element: field,
      uiTab: field.dataset.uiTab || null,
      uiOrder: this.safeInt(field.dataset.uiOrder, 999),
      uiGroup: field.dataset.uiGroup || "General",
      visibleWhen: field.dataset.visibleWhen ? this.safeJson(field.dataset.visibleWhen) : null
    }))
  }

  buildLayoutFromSchema(schema) {
    const items = []
    const elementByPath = new Map(this.fields.map((el) => [el.dataset.settingPath, el]))

    const participant = schema?.properties?.participant
    if (!participant) return null

    // Walk both llm and preset schemas
    const llm = participant?.properties?.llm
    const preset = participant?.properties?.preset

    const walk = (node, path, ctx) => {
      if (!node || typeof node !== "object") return

      const ui = node["x-ui"] || {}
      // Priority: explicit ui.group > group container label > inherited group
      const nextGroup = ui.group || ((ui.control === "group" && ui.label) ? ui.label : ctx.group)
      const nextVisibleWhen = ui.visibleWhen || ctx.visibleWhen
      const nextTab = ui.tab || ctx.tab

      const props = node.properties
      if (props && typeof props === "object") {
        Object.entries(props).forEach(([key, child]) => {
          walk(child, [...path, key], { group: nextGroup, visibleWhen: nextVisibleWhen, tab: nextTab })
        })
        return
      }

      const type = this.normalizeType(node.type)
      if (!type || type === "object") return

      const settingPath = `settings.${path.join(".")}`
      const element = elementByPath.get(settingPath)
      if (!element) return

      const leafUi = node["x-ui"] || {}

      items.push({
        element,
        uiTab: leafUi.tab || nextTab || null,
        uiOrder: this.safeInt(leafUi.order, 999),
        // Leaf node's group takes precedence over inherited group
        uiGroup: leafUi.group || nextGroup || "General",
        visibleWhen: nextVisibleWhen || null
      })
    }

    if (llm) {
      walk(llm, ["llm"], { group: null, visibleWhen: null, tab: "basic" })
    }
    if (preset) {
      walk(preset, ["preset"], { group: null, visibleWhen: null, tab: "prompts" })
    }

    return items.length ? items : null
  }

  normalizeType(type) {
    if (Array.isArray(type)) {
      const t = type.find((x) => x !== "null")
      return t || null
    }
    return typeof type === "string" ? type : null
  }

  safeInt(value, fallback) {
    const n = typeof value === "number" ? value : parseInt(value, 10)
    return Number.isFinite(n) ? n : fallback
  }

  safeJson(raw) {
    try {
      return JSON.parse(raw)
    } catch {
      return null
    }
  }

  readValueForRef(ref) {
    const settingPath = this.resolveRefSettingPath(ref)
    if (!settingPath) return undefined

    const input = this.element.querySelector(`[data-setting-path='${settingPath}'][data-setting-key]`)
    if (!input) return undefined

    return this.readInputValue(input)
  }

  resolveRefSettingPath(ref) {
    if (typeof ref !== "string" || ref.length === 0) return null

    // Absolute refs
    if (ref.startsWith("settings.") || ref.startsWith("data.")) return ref

    const direct = this.element.querySelector(`[data-setting-path='${ref}'][data-setting-key]`)
    if (direct) return ref

    const settings = this.element.querySelector(`[data-setting-path='settings.${ref}'][data-setting-key]`)
    if (settings) return `settings.${ref}`

    const data = this.element.querySelector(`[data-setting-path='data.${ref}'][data-setting-key]`)
    if (data) return `data.${ref}`

    return null
  }

  readInputValue(input) {
    if (input.type === "checkbox") {
      return input.checked
    }

    const rawValue = input.value
    const type = input.dataset.settingType

    switch (type) {
      case "integer":
        return rawValue === "" ? null : parseInt(rawValue, 10)
      case "number":
        return rawValue === "" ? null : parseFloat(rawValue)
      case "array":
      case "json":
        try {
          return JSON.parse(rawValue)
        } catch {
          return rawValue
        }
      default:
        return rawValue
    }
  }
}
