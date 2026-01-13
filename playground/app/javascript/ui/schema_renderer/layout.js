function normalizeType(type) {
  if (Array.isArray(type)) {
    const t = type.find((x) => x !== "null")
    return t || null
  }
  return typeof type === "string" ? type : null
}

function safeInt(value, fallback) {
  const n = typeof value === "number" ? value : parseInt(value, 10)
  return Number.isFinite(n) ? n : fallback
}

function safeJson(raw) {
  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

export function layoutFromDataAttributes(fields) {
  return fields.map((field) => ({
    element: field,
    uiTab: field.dataset.uiTab || null,
    uiOrder: safeInt(field.dataset.uiOrder, 999),
    uiGroup: field.dataset.uiGroup || "General",
    visibleWhen: field.dataset.visibleWhen ? safeJson(field.dataset.visibleWhen) : null
  }))
}

export function buildLayoutFromSchema(schema, fields) {
  const items = []
  const elementByPath = new Map(fields.map((el) => [el.dataset.settingPath, el]))

  const participant = schema?.properties?.participant
  if (!participant) return null

  const llm = participant?.properties?.llm
  const preset = participant?.properties?.preset

  const walk = (node, path, ctx) => {
    if (!node || typeof node !== "object") return

    const ui = node["x-ui"] || {}
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

    const type = normalizeType(node.type)
    if (!type || type === "object") return

    const settingPath = `settings.${path.join(".")}`
    const element = elementByPath.get(settingPath)
    if (!element) return

    const leafUi = node["x-ui"] || {}

    items.push({
      element,
      uiTab: leafUi.tab || nextTab || null,
      uiOrder: safeInt(leafUi.order, 999),
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
