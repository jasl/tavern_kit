import { setStatusBadge } from "../status_badge"

export function setStatus(controller, status) {
  if (!controller.hasStatusTarget) return

  setStatusBadge(controller.statusTarget, status, {
    variants: { saving: "badge-warning" },
    idleVariant: "badge-ghost"
  })
}

export function setSavedAt(controller, isoString) {
  if (!controller.hasSavedAtTarget) return

  try {
    const date = new Date(isoString)
    controller.savedAtTarget.textContent = `Last saved: ${date.toLocaleTimeString()}`
  } catch {
    controller.savedAtTarget.textContent = ""
  }
}
