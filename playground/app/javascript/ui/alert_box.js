const VARIANT_CLASSES = [
  "alert-success",
  "alert-error",
  "alert-warning",
  "alert-info"
]

function normalizeVariantClass(variant) {
  if (!variant) return null
  if (variant.startsWith("alert-")) return variant
  return `alert-${variant}`
}

function clearVariantClasses(el) {
  if (!el) return
  el.classList.remove(...VARIANT_CLASSES)
}

function applyTextOrNode(target, value) {
  if (!target) return

  target.replaceChildren()
  if (value === undefined || value === null || value === "") {
    target.hidden = true
    return
  }

  target.hidden = false
  if (value instanceof Node) {
    target.append(value)
  } else {
    target.textContent = String(value)
  }
}

export function renderAlertBox(options = {}) {
  const {
    variant = null,
    icon = "info",
    title = "",
    message = null,
    className = null,
    iconSizeClass = "size-5"
  } = options

  const template = document.getElementById("alert_box_template")
  if (!template) {
    const root = document.createElement("div")
    root.className = "alert"

    const iconEl = document.createElement("span")
    iconEl.className = `icon-[lucide--${icon}] ${iconSizeClass} shrink-0`

    const body = document.createElement("div")
    body.className = "flex-1"

    const titleEl = document.createElement("p")
    titleEl.className = "font-medium"

    const messageEl = document.createElement("p")
    messageEl.className = "text-sm opacity-80"

    applyTextOrNode(titleEl, title)
    applyTextOrNode(messageEl, message)

    body.append(titleEl, messageEl)
    root.append(iconEl, body)

    const variantClass = normalizeVariantClass(variant)
    if (variantClass) root.classList.add(variantClass)
    if (className) root.classList.add(...className.split(" "))

    return root
  }

  const root = template.content.cloneNode(true).firstElementChild
  if (!root) return document.createElement("div")

  clearVariantClasses(root)
  const variantClass = normalizeVariantClass(variant)
  if (variantClass) root.classList.add(variantClass)

  if (className) root.classList.add(...className.split(" "))

  const iconEl = root.querySelector("[data-alert-icon]")
  if (iconEl) {
    iconEl.className = `icon-[lucide--${icon}] ${iconSizeClass} shrink-0`
  }

  const titleEl = root.querySelector("[data-alert-title]")
  const messageEl = root.querySelector("[data-alert-message]")
  applyTextOrNode(titleEl, title)
  applyTextOrNode(messageEl, message)

  return root
}

