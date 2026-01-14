import { showToast } from "../../request_helpers"
import { loadAutoRefreshPreference, saveAutoRefreshPreference } from "./storage"
import { startAutoRefresh, stopAutoRefresh } from "./timer"

export function connect(controller) {
  controller.refreshTimer = null

  const shouldEnable = loadAutoRefreshPreference()

  if (controller.hasToggleTarget) {
    controller.toggleTarget.checked = shouldEnable
  }

  if (shouldEnable) {
    startAutoRefresh(controller)
  }
}

export function disconnect(controller) {
  stopAutoRefresh(controller)
}

export function toggle(controller) {
  const enabled = controller.toggleTarget.checked
  saveAutoRefreshPreference(enabled)

  if (enabled) {
    startAutoRefresh(controller)
    showToast("Auto-refresh enabled", "info", 2000)
  } else {
    stopAutoRefresh(controller)
    showToast("Auto-refresh disabled", "info", 2000)
  }
}
