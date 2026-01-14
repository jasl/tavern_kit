const VARIANT_CLASSES = [
  "badge-warning",
  "badge-info",
  "badge-success",
  "badge-error",
  "badge-ghost"
]

const DEFAULT_LABELS = {
  pending: "Unsaved",
  saving: "Saving...",
  saved: "Saved",
  error: "Error"
}

const DEFAULT_VARIANTS = {
  pending: "badge-warning",
  saving: "badge-info",
  saved: "badge-success",
  error: "badge-error"
}

function ensureBadgeBaseClasses(el) {
  if (!el) return

  el.classList.add("badge", "badge-sm")
}

function clearVariantClasses(el) {
  if (!el) return
  el.classList.remove(...VARIANT_CLASSES)
}

function clearExistingTimer(el) {
  if (!el) return

  if (el.__statusBadgeTimerId) {
    clearTimeout(el.__statusBadgeTimerId)
    el.__statusBadgeTimerId = null
  }
}

/**
 * Update a daisyUI badge-like element to reflect a status.
 *
 * Supported statuses: pending, saving, saved, error.
 *
 * Options:
 * - `message`: overrides the label (useful for error details)
 * - `labels`: per-status label overrides
 * - `variants`: per-status variant class overrides (badge-warning/info/success/error/ghost)
 * - `idleVariant`: applied when clearing (e.g. "badge-ghost")
 * - `clearAfterMs`: auto-clear delay for "saved" (default 2000; set 0 to disable)
 * - `shouldClear`: called before clearing "saved" (default always true)
 */
export function setStatusBadge(el, status, options = {}) {
  if (!el) return

  const {
    message,
    labels: labelsOverride,
    variants: variantsOverride,
    idleVariant = null,
    clearAfterMs = 2000,
    shouldClear = () => true
  } = options

  const labels = { ...DEFAULT_LABELS, ...(labelsOverride || {}) }
  const variants = { ...DEFAULT_VARIANTS, ...(variantsOverride || {}) }

  ensureBadgeBaseClasses(el)
  clearExistingTimer(el)
  clearVariantClasses(el)

  const label = message || labels[status] || ""
  const variant = variants[status] || null

  if (variant) el.classList.add(variant)

  switch (status) {
    case "pending":
    case "saving":
    case "error":
      el.textContent = label
      break
    case "saved":
      el.textContent = label

      if (clearAfterMs > 0) {
        el.__statusBadgeTimerId = setTimeout(() => {
          if (!shouldClear()) return
          clearVariantClasses(el)
          if (idleVariant) el.classList.add(idleVariant)
          el.textContent = ""
          el.__statusBadgeTimerId = null
        }, clearAfterMs)
      }
      break
    default:
      if (idleVariant) el.classList.add(idleVariant)
      el.textContent = ""
      break
  }
}

