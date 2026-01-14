import { setStatusBadge } from "../status_badge"

export function updateStatus(controller, status, message = null) {
  if (!controller.hasStatusTarget) return

  setStatusBadge(controller.statusTarget, status, {
    message,
    shouldClear: () => controller.pendingChanges.size === 0
  })
}
