export function el(tagName, options = {}, children = []) {
  const element = document.createElement(tagName)

  const { className, text, attrs, dataset } = options

  if (className) element.className = className
  if (text !== undefined && text !== null) element.textContent = String(text)

  if (attrs) {
    for (const [key, value] of Object.entries(attrs)) {
      if (value === undefined || value === null) continue
      element.setAttribute(key, String(value))
    }
  }

  if (dataset) {
    for (const [key, value] of Object.entries(dataset)) {
      if (value === undefined || value === null) continue
      element.dataset[key] = String(value)
    }
  }

  for (const child of children) {
    if (child === undefined || child === null) continue
    element.append(child)
  }

  return element
}

export function lucide(iconName, sizeClass = "size-4") {
  return el("span", { className: `icon-[lucide--${iconName}] ${sizeClass}` })
}
