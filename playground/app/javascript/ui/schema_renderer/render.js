import { layoutFromDataAttributes } from "./layout"
import { getTabTarget } from "./targets"

export function renderForTab(controller, tab) {
  controller.fields.forEach((field) => controller.poolTarget.appendChild(field))

  controller.constructor.TABS.forEach((tabName) => {
    const target = getTabTarget(controller, tabName)
    if (target) target.innerHTML = ""
  })

  const destination = getTabTarget(controller, tab)
  if (!destination) return

  const items = controller.layout || layoutFromDataAttributes(controller.fields)
  const selected = items.filter((i) => i.uiTab === tab)

  const groups = groupItems(selected)
  groups.forEach(({ label, items: groupItems }) => {
    const { container, content } = buildGroup(label)
    groupItems.forEach((i) => content.appendChild(i.element))
    destination.appendChild(container)
  })

  controller.applyVisibility()
}

function groupItems(items) {
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

function buildGroup(label) {
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
