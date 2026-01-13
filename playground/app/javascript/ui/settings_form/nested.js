export function digValue(root, dottedPath) {
  if (!root || typeof root !== "object") return undefined

  const parts = dottedPath.split(".").filter(Boolean)
  let current = root

  for (const part of parts) {
    if (!current || typeof current !== "object") return undefined
    if (!Object.prototype.hasOwnProperty.call(current, part)) return undefined
    current = current[part]
  }

  return current
}

export function assignNested(root, dottedPath, value) {
  const parts = dottedPath.split(".").filter(Boolean)
  if (parts.length === 0) return

  let current = root

  for (let i = 0; i < parts.length - 1; i++) {
    const segment = parts[i]
    if (typeof current[segment] !== "object" || current[segment] === null || Array.isArray(current[segment])) {
      current[segment] = {}
    }
    current = current[segment]
  }

  current[parts[parts.length - 1]] = value
}
